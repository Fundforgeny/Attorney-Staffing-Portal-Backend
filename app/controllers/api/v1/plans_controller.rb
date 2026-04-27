class Api::V1::PlansController < ActionController::API
  include ApiResponse
  include Devise::Controllers::Helpers

  before_action :validate_create_params, only: [ :create ]
  before_action :set_plan, only: [ :show, :generate_agreement, :mark_payment_success, :mark_payment_failed, :cancel_payment ]
  before_action :authenticate_user!, only: [ :update_next_payment_at ]
  before_action :set_current_user_plan, only: [ :update_next_payment_at ]

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

    GhlPlanSyncWorker.perform_async(plan.id, GhlInboundWebhookService.plan_created_event) if created && plan.persisted?

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
    if @plan.paid?
      return render_success(
        data: serialized_plan(@plan),
        message: "Plan is already paid",
        status: :ok
      )
    end

    succeeded_payment = @plan.payments.where(status: :succeeded).order(paid_at: :desc).first
    unless succeeded_payment.present?
      return render_error(
        message: "Cannot mark paid without a successful charged payment",
        status: :unprocessable_entity
      )
    end

    @plan.update!(status: :paid)
    GhlInboundWebhookWorker.perform_async(succeeded_payment.id)
    render_success(data: serialized_plan(@plan), message: "Plan marked as paid", status: :ok)
  end

  def mark_payment_failed
    return render_error(message: "Paid plan cannot be marked as failed", status: :unprocessable_entity) if @plan.paid?

    @plan.update!(status: :failed)
    failed_payment = @plan.payments.where(status: :failed).order(updated_at: :desc).first
    GhlInboundWebhookWorker.perform_async(failed_payment.id, GhlInboundWebhookService::PAYMENT_FAILED_EVENT) if failed_payment.present?
    render_success(data: serialized_plan(@plan), message: "Plan marked as failed", status: :ok)
  end

  def cancel_payment
    return render_error(message: "Paid plan cannot be cancelled", status: :unprocessable_entity) if @plan.paid?

    # Revert the plan back to agreement_generated so the checkout flow
    # resumes at the Agreement step instead of the Payment step.
    if @plan.payment_pending? || @plan.failed?
      @plan.update!(status: :agreement_generated)
    end
    render_success(data: serialized_plan(@plan), message: "Payment cancelled", status: :ok)
  end

  def update_next_payment_at
    payment = @plan.next_scheduled_monthly_payment
    current_next_payment_at = payment&.scheduled_at || @plan.next_payment_at
    return render_error(message: "No upcoming monthly payment found for this plan", status: :unprocessable_entity) if current_next_payment_at.blank?

    next_payment_at = parse_next_payment_at_param
    return if performed?

    unless same_billing_month?(current_next_payment_at: current_next_payment_at, requested_next_payment_at: next_payment_at)
      return render_error(
        message: "Next payment date can only be changed within #{current_next_payment_at.strftime('%B %Y')}",
        status: :unprocessable_entity
      )
    end

    ActiveRecord::Base.transaction do
      payment&.update!(scheduled_at: next_payment_at)

      if payment.present?
        @plan.refresh_next_payment_at!
      else
        @plan.update!(next_payment_at: next_payment_at)
      end
    end

    render_success(
      data: serialized_plan(@plan.reload),
      message: "Next payment date updated successfully",
      status: :ok
    )
  rescue ActiveRecord::RecordInvalid => e
    render_error(errors: e.record.errors.full_messages, status: :unprocessable_entity)
  end

  private

  def set_plan
    @plan = Plan.find_by(checkout_session_id: params[:checkout_session_id])
    return if @plan.present?

    render_error(message: "Plan not found", status: :not_found)
  end

  def set_current_user_plan
    @plan = current_user.plans.find_by(id: params[:id])
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
    email = email.to_s.strip.downcase
    user = User.find_or_initialize_by(email: email)
    name_param = normalized_create_params[:name].to_s.strip
    if user.new_record?
      if name_param.present?
        parts = name_param.split(" ", 2)
        user.first_name = parts[0].presence || "Checkout"
        user.last_name  = parts[1].presence || ""
      else
        user.first_name = "Checkout"
        user.last_name  = "User"
      end
      user.user_type = :client
      user.skip_confirmation!
      user.save!
    elsif name_param.present? && user.first_name.in?([nil, "", "Checkout"])
      # Update placeholder name with real name when provided
      parts = name_param.split(" ", 2)
      user.update_columns(
        first_name: parts[0].presence || user.first_name,
        last_name:  parts[1].presence || user.last_name
      )
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
    user = plan.user
    {
      id: plan.id,
      plan_id: plan.id,
      user_id: plan.user_id,
      customer_name: user&.full_name,
      email: user&.email,
      phone: user&.phone,
      plan_name: plan.name,
      name: plan.name,
      checkout_session_id: plan.checkout_session_id,
      status: plan.status,
      total_amount: plan.total_payment.to_d,
      down_payment: plan.down_payment.to_d,
      months: plan.duration,
      next_payment_at: plan.next_payment_at,
      agreement_id: agreement&.id,
      agreement_content: nil,
      fund_forge_agreement_url: agreement&.pdf&.attached? ? agreement.pdf.url : nil,
      engagement_agreement_url: agreement&.engagement_pdf&.attached? ? agreement.engagement_pdf.url : nil,
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

  def parse_next_payment_at_param
    next_payment_at_value = params[:next_payment_at].to_s
    if next_payment_at_value.blank?
      render_error(message: "next_payment_at is required", status: :bad_request)
      return
    end

    parsed_value = Time.zone.parse(next_payment_at_value)
    if parsed_value.blank?
      render_error(message: "next_payment_at must be a valid date", status: :bad_request)
      return
    end

    parsed_value
  rescue ArgumentError, TypeError
    render_error(message: "next_payment_at must be a valid date", status: :bad_request)
    nil
  end

  def same_billing_month?(current_next_payment_at:, requested_next_payment_at:)
    return false if requested_next_payment_at.blank? || current_next_payment_at.blank?

    current_next_payment_at.year == requested_next_payment_at.year &&
      current_next_payment_at.month == requested_next_payment_at.month
  end

  def serialized_attachment(attachment)
    return nil unless attachment&.attached?

    {
      url: attachment.url,
      filename: attachment.filename.to_s
    }
  end
end
