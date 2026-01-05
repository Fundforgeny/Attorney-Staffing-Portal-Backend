# app/controllers/api/v1/payments_controller.rb
class Api::V1::PaymentsController < ActionController::API
  include ApiResponse

  def create_user_plan
    ActiveRecord::Base.transaction do
      user = create_or_find_user
      plan = create_plan_instance(user)

      # Generate the filled agreement PDF (returns a file path)
      pdf_path = AgreementPdfGenerator.new(user, plan).generate
      filename = "fund_forge_agreement_#{plan.id}.pdf"
      agreement = Agreement.create( user: user, plan: plan)

      agreement.pdf.attach(
        io: File.open(pdf_path),
        filename: filename,
        content_type: "application/pdf"
      )
      agreement_url = Rails.application.routes.url_helpers.rails_blob_url(agreement.pdf, only_path: true)

      render_success(
        data: {
          user: user.as_json(only: [:id, :first_name, :last_name, :email]),
          plan: plan.as_json(except: [:created_at, :updated_at]),
          agreement_url: agreement_url,
          agreement_filename: filename,
        },
        message: "User and plan created successfully with signed agreement",
        status: :created
      )
    end
  rescue StandardError => e
    render_error(message: e.message, status: :unprocessable_entity)
  end


  def checkout
    ActiveRecord::Base.transaction do
      user = User.find(params[:user_id])
      plan = Plan.find(params[:plan_id])
      raise ArgumentError, "Plan does not belong to user" if plan.user != user

      payment_method = store_vault_token(user)
      payments = create_payment_schedule(plan, payment_method)
      payments.each do |payment|
        payment.update!(payment_method: payment_method)
      end

      result = StripePaymentService.new(payments)
      # result = SquarePaymentService.new(payments)

      render_success(
        data: {
          user: user,
          plan: plan,
          payments: payments.map { |p| payment_serializer(p) }
        },
        message: "Checkout completed successfully",
        status: :created
      )
    end
  rescue StandardError => e
    render_error(message: e.message)
  end

  def create_verification_session
    begin
      verification_session = Stripe::Identity::VerificationSession.create(
        type: 'document'
      )

      render_success(
        data: {
          client_secret: verification_session.client_secret
        },
        message: "Verification session created successfully",
        status: :created
      )
    rescue Stripe::StripeError => e
      render_error(message: e.message)
    end
  end

  private

  def create_or_find_user
    full_name = params[:user][:name]
    email     = params[:user][:email].downcase.strip

    raise ArgumentError, "Name and email are required" if full_name.blank? || email.blank?

    name_parts  = full_name.split(" ", 2)
    first_name  = name_parts[0]
    last_name   = name_parts[1] || ""

    User.find_or_create_by!(email: email) do |u|
      u.first_name = first_name
      u.last_name  = last_name
      u.user_type = "client"
    end
  end

  def store_vault_token(user)
    vault_token = params[:payment_method][:vault_token]
    raise ArgumentError, "vault_token is required" if vault_token.blank?
    PaymentMethod.create!(
      user: user,
      provider: "stripe",
      vault_token: vault_token,
      cardholder_name: "#{user.first_name} #{user.last_name}".strip,
      last4: params[:payment_method][:vault_token]["last_four"].to_s,
      exp_month: params[:payment_method][:vault_token]["exp_month"].to_s,
      exp_year: params[:payment_method][:vault_token]["exp_year"].to_s,
      card_brand: params[:payment_method][:vault_token]["type"]
    )
  end

  def create_plan_instance(user)
    plan_params = params[:plan]

    Plan.create!(
      user: user,
      name: plan_params[:name],
      duration: plan_params[:duration],
      total_payment: plan_params[:total_payment],
      total_interest_amount: plan_params[:total_interest],
      monthly_payment: plan_params[:monthly_payment],
      monthly_interest_amount: plan_params[:monthly_interest],
      down_payment: plan_params[:down_payment],
      status: :active
    )
  end

  def create_payment_schedule(plan, payment_method)
    payments = []
    plan_params = params[:plan]

    # Down payment
    if plan.down_payment > 0
      payments << Payment.create!(
        plan: plan,
        user: plan.user,
        payment_method: payment_method,
        payment_type: plan_params[:name] ? :full_payment : :down_payment,
        payment_amount: plan.down_payment,
        total_payment_including_fee: (plan.down_payment * 1.03).round(2),
        transaction_fee: (plan.down_payment * 0.03).round(2),
        status: :pending,
        scheduled_at: Time.current
      )
    end

    # Monthly installments
    start_date = plan_params[:first_installment_date].present? ?
                 Date.parse(plan_params[:first_installment_date]) :
                 nil

    if plan.duration > 0
      plan.duration.times do |i|
        payments << Payment.create!(
          plan: plan,
          user: plan.user,
          payment_method: payment_method,
          payment_type: :monthly_payment,
          payment_amount: plan.monthly_payment,
          total_payment_including_fee: (plan.monthly_payment * 1.03).round(2),
          transaction_fee: (plan.monthly_payment * 0.03).round(2),
          status: :pending,
          scheduled_at: start_date + i.months
        )
      end
    end
    payments
  end

  def payment_serializer(payment)
    {
      id: payment.id,
      type: payment.payment_type,
      amount: payment.payment_amount,
      status: payment.status,
      scheduled_at: payment.scheduled_at,
      paid_at: payment.paid_at,
      charge_id: payment.charge_id
    }
  end
end
