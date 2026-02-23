class Api::V1::Auth::LoginLinksController < ActionController::API
  include ApiResponse

  def create
    email = params[:email].to_s.strip.downcase
    return render_error(message: "Email is required", status: :bad_request) if email.blank?

    user = User.find_by(email: email)
    return render_error(message: "User not found", status: :not_found) if user.nil?

    login_magic_link = LoginLinkService.new(user: user).generate_link
    
    GhlWebhookService.send_login_magic_link!(user: user, login_magic_link: login_magic_link)
    puts "Login magic link: #{login_magic_link}"
    render_success(
      data: { email: user.email },
      message: "Login link sent successfully",
      status: :ok
    )
  rescue StandardError => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def show
    token = params[:token]
    verified_user = LoginLinkService.verify!(token)
    user = User.includes(:payment_method, :firm, :firms, agreements: :plan, plans: [ :agreement, :payments ]).find(verified_user.id)
    auth_token, = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)

    render_success(
      data: {
        auth_token: auth_token,
        user: serialized_user(user)
      },
      message: "Login link verified successfully",
      status: :ok
    )
  rescue LoginLinkService::InvalidTokenError => e
    render_error(message: e.message, status: :unprocessable_entity)
  rescue LoginLinkService::ExpiredTokenError => e
    render_error(message: e.message, status: :unprocessable_entity)
  rescue LoginLinkService::UsedTokenError => e
    render_error(message: e.message, status: :unprocessable_entity)
  rescue StandardError => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  private

  def serialized_user(user)
    {
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      phone: user.phone,
      user_type: user.user_type,
      firm_id: user.firm_id,
      payment_method: serialized_payment_method(user.payment_method),
      primary_firm: serialized_firm(user.firm),
      firms: user.firms.map { |firm| serialized_firm(firm) },
      plans: user.plans.map { |plan| serialized_plan(plan) },
      agreements: user.agreements.map { |agreement| serialized_agreement(agreement) }
    }
  end

  def serialized_plan(plan)
    {
      id: plan.id,
      name: plan.name,
      status: plan.status,
      duration: plan.duration,
      total_payment: plan.total_payment,
      down_payment: plan.down_payment,
      monthly_payment: plan.monthly_payment,
      total_interest_amount: plan.total_interest_amount,
      monthly_interest_amount: plan.monthly_interest_amount,
      base_legal_fee: plan.base_legal_fee_amount,
      payment_plan_selected: plan.payment_plan_selected?,
      administration_fee_name: plan.administration_fee_name,
      administration_fee_percentage: plan.administration_fee_percentage,
      administration_fee_amount: plan.administration_fee_amount,
      total_payment_plan_amount: plan.total_payment_plan_amount,
      created_at: plan.created_at,
      updated_at: plan.updated_at,
      payments: plan.payments.map { |payment| serialized_payment(payment) },
      agreement: serialized_agreement(plan.agreement)
    }
  end

  def serialized_payment(payment)
    {
      id: payment.id,
      plan_id: payment.plan_id,
      payment_method_id: payment.payment_method_id,
      payment_type: payment.payment_type,
      status: payment.status,
      payment_amount: payment.payment_amount,
      total_payment_including_fee: payment.total_payment_including_fee,
      transaction_fee: payment.transaction_fee,
      administration_fee_amount: payment.transaction_fee,
      charge_id: payment.charge_id,
      scheduled_at: payment.scheduled_at,
      paid_at: payment.paid_at,
      created_at: payment.created_at,
      updated_at: payment.updated_at
    }
  end

  def serialized_payment_method(payment_method)
    return nil if payment_method.blank?

    {
      id: payment_method.id,
      provider: payment_method.provider,
      card_brand: payment_method.card_brand,
      last4: payment_method.last4,
      exp_month: payment_method.exp_month,
      exp_year: payment_method.exp_year,
      cardholder_name: payment_method.cardholder_name,
      created_at: payment_method.created_at,
      updated_at: payment_method.updated_at
    }
  end

  def serialized_firm(firm)
    return nil if firm.blank?

    {
      id: firm.id,
      name: firm.name,
      description: firm.description,
      primary_color: firm.primary_color,
      secondary_color: firm.secondary_color,
      location_id: firm.location_id,
      created_at: firm.created_at,
      updated_at: firm.updated_at
    }
  end

  def serialized_agreement(agreement)
    return nil if agreement.blank?

    {
      id: agreement.id,
      user_id: agreement.user_id,
      plan_id: agreement.plan_id,
      signed_at: agreement.signed_at,
      pdf_url: agreement_attachment_url(agreement.pdf),
      engagement_pdf_url: agreement_attachment_url(agreement.engagement_pdf),
      signature_url: agreement_attachment_url(agreement.signature),
      created_at: agreement.created_at,
      updated_at: agreement.updated_at
    }
  end

  def agreement_attachment_url(attachment)
    return nil unless attachment.attached?
    return nil unless attachment.blob.service.exist?(attachment.key)

    rails_blob_url(attachment, disposition: "inline")
  rescue StandardError => e
    Rails.logger.warn("Agreement attachment URL generation failed for blob #{attachment.blob_id}: #{e.message}")
    nil
  end
end

