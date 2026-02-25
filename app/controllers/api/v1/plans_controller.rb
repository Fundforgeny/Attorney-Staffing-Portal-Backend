class Api::V1::PlansController < ActionController::API
  include ApiResponse

  before_action :validate_create_params, only: [ :create ]
  before_action :set_plan, only: [ :show, :generate_agreement, :mark_payment_success, :mark_payment_failed ]

  def create
    retries = 0
    plan = nil
    created = false

    begin
      ActiveRecord::Base.transaction do
        plan = Plan.find_or_initialize_by(checkout_session_id: normalized_create_params[:checkout_session_id])
        user = resolve_user!(plan)

        return render_error(message: "Plan is already paid", status: :unprocessable_entity) if plan.persisted? && plan.paid?
        return render_error(message: "Plan is expired", status: :unprocessable_entity) if plan.persisted? && plan.expired?

        created = plan.new_record?
        assign_plan_attributes(plan, user)
        plan.status = :draft if plan.new_record? || plan.failed?
        plan.save!
      end
    rescue ActiveRecord::RecordNotUnique
      retries += 1
      retry if retries <= 1
      raise
    end

    render_success(
      data: serialized_plan(plan),
      message: created ? "Plan created successfully" : "Plan updated successfully",
      status: created ? :created : :ok
    )
  rescue ActiveRecord::RecordInvalid => e
    render_error(errors: e.record.errors.full_messages, status: :unprocessable_entity)
  rescue ArgumentError => e
    render_error(message: e.message, status: :bad_request)
  end

  def show
    render_success(data: serialized_plan(@plan), status: :ok)
  end

  def generate_agreement
    agreement = @plan.agreement || Agreement.create!(user: @plan.user, plan: @plan)
    AgreementAttachmentService.new(agreement).attach_agreements

    @plan.update!(status: :agreement_generated) if @plan.draft?
    render_success(data: serialized_plan(@plan.reload), message: "Agreement generated", status: :ok)
  rescue StandardError => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def mark_payment_success
    return render_error(message: "Plan is already paid", status: :unprocessable_entity) if @plan.paid?

    succeeded_payment = @plan.payments.where(status: :succeeded).order(paid_at: :desc).first
    unless succeeded_payment.present?
      return render_error(
        message: "Cannot mark paid without a successful charged payment",
        status: :unprocessable_entity
      )
    end

    @plan.update!(status: :paid)
    render_success(data: serialized_plan(@plan), message: "Plan marked as paid", status: :ok)
  end

  def mark_payment_failed
    return render_error(message: "Paid plan cannot be marked as failed", status: :unprocessable_entity) if @plan.paid?

    @plan.update!(status: :failed)
    render_success(data: serialized_plan(@plan), message: "Plan marked as failed", status: :ok)
  end

  private

  def set_plan
    @plan = Plan.find_by(checkout_session_id: params[:checkout_session_id])
    return if @plan.present?

    render_error(message: "Plan not found", status: :not_found)
  end

  def normalized_create_params
    @normalized_create_params ||= begin
      top_level = params.permit(:checkout_session_id, :email, :name, :total_amount, :down_payment, :months, :duration).to_h
      nested_plan = params.permit(plan: [ :checkout_session_id, :email, :name, :total_amount, :down_payment, :months, :duration ])
                          .fetch(:plan, {})
                          .to_h

      ActionController::Parameters.new(nested_plan.merge(top_level))
                                  .permit(:checkout_session_id, :email, :name, :total_amount, :down_payment, :months, :duration)
    end
  end

  def validate_create_params
    missing_params = [ :checkout_session_id ].select { |key| normalized_create_params[key].blank? }
    return render_error(message: "Missing required parameters: #{missing_params.join(', ')}", status: :bad_request) if missing_params.any?

    existing_plan = Plan.find_by(checkout_session_id: normalized_create_params[:checkout_session_id])
    if existing_plan.blank?
      create_missing_params = [ :email, :total_amount, :down_payment ].select { |key| normalized_create_params[key].blank? }
      return render_error(message: "Missing required parameters: #{create_missing_params.join(', ')}", status: :bad_request) if create_missing_params.any?
    end

    return if requested_months.blank?

    unless [ 0, 3, 6, 9, 12 ].include?(requested_months.to_i)
      render_error(message: "months must be one of: 0, 3, 6, 9, 12", status: :bad_request)
    end
  end

  def resolve_user!(plan)
    return plan.user if plan.persisted? && plan.user.present? && normalized_create_params[:email].blank?
    return find_or_create_user!(normalized_create_params[:email]) if normalized_create_params[:email].present?

    raise ArgumentError, "Missing required parameters: email"
  end

  def find_or_create_user!(email)
    user = User.find_or_initialize_by(email: email)
    if user.new_record?
      user.first_name = "Checkout"
      user.last_name = "User"
      user.user_type = :client
      user.skip_confirmation!
      user.save!
    end
    user
  end

  def assign_plan_attributes(plan, user)
    months = requested_months.present? ? requested_months.to_i : plan.duration
    total_amount = normalized_create_params[:total_amount].present? ? normalized_create_params[:total_amount].to_d : plan.total_payment
    down_payment = normalized_create_params[:down_payment].present? ? normalized_create_params[:down_payment].to_d : plan.down_payment
    total_amount ||= 0.to_d
    down_payment ||= 0.to_d

    selected_payment_plan = PaymentPlanFeeCalculator.plan_selected?(selected_payment_plan: true, duration: months)
    fee_calculator = PaymentPlanFeeCalculator.new(base_amount: total_amount, selected_payment_plan: selected_payment_plan)
    administration_fee = fee_calculator.fee_amount
    financed_amount = [ total_amount - down_payment, 0.to_d ].max

    plan.assign_attributes(
      user: user,
      name: normalized_create_params[:name].presence || plan.name.presence || "checkout_plan",
      duration: months,
      total_payment: total_amount,
      down_payment: down_payment,
      total_interest_amount: administration_fee,
      monthly_interest_amount: months.present? && months.positive? ? (administration_fee / months).round(2) : 0,
      monthly_payment: months.present? && months.positive? ? (financed_amount / months).round(2) : 0
    )
  end

  def requested_months
    normalized_create_params[:months].presence || normalized_create_params[:duration].presence
  end

  def serialized_plan(plan)
    agreement = plan.agreement
    {
      id: plan.id,
      user_id: plan.user_id,
      name: plan.name,
      checkout_session_id: plan.checkout_session_id,
      status: plan.status,
      total_amount: plan.total_payment.to_d,
      down_payment: plan.down_payment.to_d,
      months: plan.duration,
      agreement_id: agreement&.id,
      fund_forge_agreement: serialized_attachment(agreement&.pdf),
      engagement_agreement: serialized_attachment(agreement&.engagement_pdf),
      installments: plan.payments.order(:scheduled_at).map do |payment|
        {
          id: payment.id,
          payment_type: payment.payment_type,
          amount: payment.payment_amount,
          scheduled_at: payment.scheduled_at,
          status: payment.status
        }
      end
    }
  end

  def serialized_attachment(attachment)
    return nil unless attachment&.attached?

    {
      url: attachment.url,
      filename: attachment.filename.to_s
    }
  end
end

