class Api::V1::Payment3dsController < ActionController::API
  include ApiResponse
  include Devise::Controllers::Helpers

  before_action :authenticate_user!, except: [ :callback ]

  def start
    user = current_user
    plan = user.plans.find(start_params[:plan_id])
    payment_method = user.payment_methods.find(start_params[:payment_method_id])
    payment = resolve_payment!(user, plan)

    callback_token = SecureRandom.hex(24)
    callback_url = "#{request.base_url}/api/v1/payments/3ds/callback?callback_token=#{callback_token}"
    redirect_url = ENV["SPREEDLY_3DS_RETURN_URL"].presence || "#{ENV.fetch('FRONTEND_APP_URL', 'http://localhost:5173').to_s.chomp('/')}/pay/3ds-complete"

    transaction = Spreedly::ThreeDsService.new.initiate_purchase(
      payment_method_token: payment_method.vault_token,
      amount_cents: (payment.total_payment_including_fee.to_d * 100).to_i,
      currency: "USD",
      callback_url: callback_url,
      redirect_url: redirect_url,
      workflow_key: composer_workflow_key
    )

    challenge_url = Spreedly::ThreeDsService.new.extract_challenge_url(transaction)
    status = derive_session_status(transaction["state"], challenge_url)
    session = Payment3dsSession.create!(
      user: user,
      plan: plan,
      payment: payment,
      payment_method: payment_method,
      status: status,
      callback_token: callback_token,
      spreedly_transaction_token: transaction["token"],
      challenge_url: challenge_url,
      raw_response: transaction
    )

    update_payment_from_transaction!(payment, plan, transaction) if terminal_transaction?(transaction["state"])

    render_success(
      data: {
        session_id: session.id,
        transaction_token: transaction["token"],
        status: session.status,
        challenge_url: challenge_url
      },
      message: status == "succeeded" ? "3DS flow already completed" : "3DS flow initiated",
      status: :ok
    )
  rescue ActiveRecord::RecordNotFound
    render_error(message: "Plan or payment method not found", status: :not_found)
  rescue Spreedly::Error => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def complete
    session = current_user.payment_3ds_sessions.find(complete_params[:session_id])
    transaction = Spreedly::ThreeDsService.new.fetch_transaction(transaction_token: session.spreedly_transaction_token)
    session.update!(raw_response: transaction, status: derive_session_status(transaction["state"], session.challenge_url))

    update_payment_from_transaction!(session.payment, session.plan, transaction) if terminal_transaction?(transaction["state"])

    render_success(
      data: {
        session_id: session.id,
        transaction_token: session.spreedly_transaction_token,
        status: session.status
      },
      message: "3DS transaction status fetched",
      status: :ok
    )
  rescue ActiveRecord::RecordNotFound
    render_error(message: "3DS session not found", status: :not_found)
  rescue Spreedly::Error => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def callback
    session = Payment3dsSession.find_by(callback_token: params[:callback_token])
    return render_error(message: "Invalid callback token", status: :not_found) if session.blank?

    transaction = params[:transaction].is_a?(ActionController::Parameters) ? params[:transaction].to_unsafe_h : params[:transaction]
    transaction ||= {}

    session.update!(
      raw_response: transaction,
      status: derive_session_status(transaction["state"], session.challenge_url),
      completed_at: terminal_transaction?(transaction["state"]) ? Time.current : nil
    )
    update_payment_from_transaction!(session.payment, session.plan, transaction) if terminal_transaction?(transaction["state"])

    render_success(message: "Callback processed", status: :ok)
  rescue StandardError => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  private

  def start_params
    params.permit(:plan_id, :payment_method_id)
  end

  def complete_params
    params.permit(:session_id)
  end

  def resolve_payment!(user, plan)
    payment_type = plan.duration.to_i > 0 ? "down_payment" : "full_payment"
    Payment.find_by!(user: user, plan: plan, payment_type: payment_type)
  end

  def derive_session_status(state, challenge_url)
    return "succeeded" if state.to_s == "succeeded"
    return "failed" if %w[failed gateway_processing_failed scrubbed].include?(state.to_s)
    return "challenged" if challenge_url.present?

    "pending"
  end

  def terminal_transaction?(state)
    Spreedly::ThreeDsService.new.terminal_state?(state)
  end

  def update_payment_from_transaction!(payment, plan, transaction)
    succeeded = ActiveModel::Type::Boolean.new.cast(transaction["succeeded"]) || transaction["state"].to_s == "succeeded"
    payment.update!(
      charge_id: transaction["token"] || payment.charge_id,
      status: succeeded ? :succeeded : :failed,
      paid_at: succeeded ? Time.current : nil
    )
    plan.update!(status: :paid) if succeeded && payment.payment_type.to_s == "full_payment"
    plan.update!(status: :failed) unless succeeded || plan.paid?
  end

  def composer_workflow_key
    ENV["SPREEDLY_WORKFLOW_KEY"].presence || ENV["SPREEDLY_COMPOSER_WORKFLOW_KEY"].presence
  end
end


