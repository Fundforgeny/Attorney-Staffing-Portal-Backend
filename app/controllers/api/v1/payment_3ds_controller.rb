class Api::V1::Payment3dsController < ActionController::API
  include ApiResponse
  include Devise::Controllers::Helpers
  include SpreedlyCallbackUrl

  before_action :authenticate_user!, except: [ :callback, :start_checkout, :complete_checkout ]

  def start
    if sca_provider_key.present? && start_params[:browser_info].blank?
      return render_error(message: "browser_info is required for 3DS2 authentication", status: :unprocessable_entity)
    end

    user = current_user
    plan = user.plans.find(start_params[:plan_id])
    payment_method = user.payment_methods.find(start_params[:payment_method_id])
    payment = resolve_payment!(user, plan)

    callback_token = SecureRandom.hex(24)
    callback_url = spreedly_three_ds_callback_url(callback_token)
    redirect_url = spreedly_three_ds_redirect_url

    tds = Spreedly::ThreeDsService.new
    raw_transaction = tds.initiate_purchase(
      payment_method_token: payment_method.vault_token,
      amount_cents: (payment.total_payment_including_fee.to_d * 100).to_i,
      currency: "USD",
      callback_url: callback_url,
      redirect_url: redirect_url,
      workflow_key: composer_workflow_key,
      gateway_token: direct_gateway_token,
      browser_info: start_params[:browser_info],
      sca_provider_key: sca_provider_key,
      ip: request.remote_ip
    )

    transaction = normalize_transaction(raw_transaction)
    challenge_url = tds.extract_challenge_url(transaction)
    status = derive_session_status(transaction["state"], challenge_url, transaction)
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

    log_three_ds_event("start", transaction, payment: payment, session_id: session.id)
    update_payment_from_transaction!(payment, plan, transaction) if terminal_transaction?(transaction["state"])

    render_success(
      data: {
        session_id: session.id,
        transaction_token: transaction["token"],
        status: session.status
      }.merge(tds.challenge_client_fields(transaction)),
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
    tds = Spreedly::ThreeDsService.new
    transaction = normalize_transaction(tds.fetch_transaction(transaction_token: session.spreedly_transaction_token))
    challenge_url = tds.extract_challenge_url(transaction)
    session.update!(
      raw_response: transaction,
      status: derive_session_status(transaction["state"], challenge_url, transaction),
      challenge_url: challenge_url,
      completed_at: terminal_transaction?(transaction["state"]) ? Time.current : nil
    )

    log_three_ds_event("complete", transaction, payment: session.payment, session_id: session.id)
    update_payment_from_transaction!(session.payment, session.plan, transaction) if terminal_transaction?(transaction["state"])

    render_success(
      data: {
        session_id: session.id,
        transaction_token: session.spreedly_transaction_token,
        status: session.status
      }.merge(tds.challenge_client_fields(transaction)),
      message: "3DS transaction status fetched",
      status: :ok
    )
  rescue ActiveRecord::RecordNotFound
    render_error(message: "3DS session not found", status: :not_found)
  rescue Spreedly::Error => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def start_checkout
    if sca_provider_key.present? && start_checkout_params[:browser_info].blank?
      return render_error(message: "browser_info is required for 3DS2 authentication", status: :unprocessable_entity)
    end

    plan = find_plan_for_checkout!
    user = User.find(start_checkout_params[:user_id])
    raise ActiveRecord::RecordNotFound, "User not found" unless plan.user_id == user.id

    return render_error(message: "Plan is already paid", status: :unprocessable_entity) if plan.paid?
    return render_error(message: "Plan is expired", status: :unprocessable_entity) if plan.expired?

    payment_method = resolve_payment_method_for_checkout!(user)
    payment = ensure_checkout_and_payment!(user, plan, payment_method)

    callback_token = SecureRandom.hex(24)
    callback_url = spreedly_three_ds_callback_url(callback_token)
    redirect_url = spreedly_three_ds_redirect_url

    amount_cents = start_checkout_params[:amount_in_cents].presence || (payment.total_payment_including_fee.to_d * 100).to_i

    tds = Spreedly::ThreeDsService.new
    raw_transaction = tds.initiate_purchase(
      payment_method_token: payment_method.vault_token,
      amount_cents: amount_cents,
      currency: "USD",
      callback_url: callback_url,
      redirect_url: redirect_url,
      workflow_key: composer_workflow_key,
      gateway_token: direct_gateway_token,
      browser_info: parse_browser_info(start_checkout_params[:browser_info]),
      sca_provider_key: sca_provider_key,
      ip: request.remote_ip
    )

    transaction = normalize_transaction(raw_transaction)
    challenge_url = tds.extract_challenge_url(transaction)
    session_status = derive_session_status(transaction["state"], challenge_url, transaction)
    session = Payment3dsSession.create!(
      user: user,
      plan: plan,
      payment: payment,
      payment_method: payment_method,
      status: session_status,
      callback_token: callback_token,
      spreedly_transaction_token: transaction["token"],
      challenge_url: challenge_url,
      raw_response: transaction
    )

    log_three_ds_event("checkout_start", transaction, payment: payment, session_id: session.id)

    if terminal_transaction?(transaction["state"])
      update_payment_from_transaction!(payment, plan, transaction)
      if transaction["state"].to_s == "succeeded"
        render_success(
          data: { checkout_completed: true, three_ds_required: false },
          message: "Payment completed successfully",
          status: :ok
        )
      else
        render_error(
          message: transaction["message"].presence || "3DS authentication failed",
          status: :unprocessable_entity
        )
      end
    else
      render_success(
        data: {
          transaction_token: transaction["token"],
          three_ds_required: true,
          session_id: session.id,
          status: session_status
        }.merge(tds.challenge_client_fields(transaction)),
        message: "3DS verification required",
        status: :ok
      )
    end
  rescue ActiveRecord::RecordNotFound => e
    render_error(message: e.message.presence || "Plan or user not found", status: :not_found)
  rescue Spreedly::Error => e
    render_error(message: e.message, status: :unprocessable_entity)
  rescue ArgumentError => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def complete_checkout
    session = Payment3dsSession.find_by(id: complete_checkout_params[:session_id])
    return render_error(message: "3DS session not found", status: :not_found) if session.blank?

    if complete_checkout_params[:transaction_token].present? && session.spreedly_transaction_token != complete_checkout_params[:transaction_token]
      return render_error(message: "Transaction token mismatch", status: :unprocessable_entity)
    end

    tds = Spreedly::ThreeDsService.new
    transaction = normalize_transaction(tds.fetch_transaction(transaction_token: session.spreedly_transaction_token))
    challenge_url = tds.extract_challenge_url(transaction)
    session.update!(
      raw_response: transaction,
      status: derive_session_status(transaction["state"], challenge_url, transaction),
      challenge_url: challenge_url,
      completed_at: terminal_transaction?(transaction["state"]) ? Time.current : nil
    )

    log_three_ds_event("checkout_complete", transaction, payment: session.payment, session_id: session.id)

    unless terminal_transaction?(transaction["state"])
      return render_success(
        data: {
          status: session.status,
          three_ds_required: true,
          session_id: session.id,
          transaction_token: session.spreedly_transaction_token
        }.merge(tds.challenge_client_fields(transaction)),
        message: "3DS verification still in progress",
        status: :ok
      )
    end

    update_payment_from_transaction!(session.payment, session.plan, transaction)
    succeeded = transaction["state"].to_s == "succeeded"

    if succeeded
      render_success(
        data: { checkout_completed: true, three_ds_required: false },
        message: "Payment completed successfully",
        status: :ok
      )
    else
      render_error(
        message: transaction["message"].presence || "3DS authentication failed",
        status: :unprocessable_entity
      )
    end
  rescue Spreedly::Error => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def callback
    session = Payment3dsSession.find_by(callback_token: params[:callback_token])
    return render_error(message: "Invalid callback token", status: :not_found) if session.blank?

    transaction = params[:transaction].is_a?(ActionController::Parameters) ? params[:transaction].to_unsafe_h : params[:transaction]
    transaction = normalize_transaction(transaction || {})

    tds = Spreedly::ThreeDsService.new
    challenge_url = tds.extract_challenge_url(transaction)
    session.update!(
      raw_response: transaction,
      status: derive_session_status(transaction["state"], challenge_url, transaction),
      challenge_url: challenge_url,
      completed_at: terminal_transaction?(transaction["state"]) ? Time.current : nil
    )
    log_three_ds_event("callback", transaction, payment: session.payment, session_id: session.id)
    update_payment_from_transaction!(session.payment, session.plan, transaction) if terminal_transaction?(transaction["state"])

    render_success(message: "Callback processed", status: :ok)
  rescue StandardError => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  private

  def start_params
    params.permit(:plan_id, :payment_method_id, browser_info: {})
  end

  def complete_params
    params.permit(:session_id)
  end

  def start_checkout_params
    params.permit(:checkout_session_id, :user_id, :plan_id, :vault_token, :card_brand, :amount_in_cents, :first_installment_date, :cardholder_name, :billing_email, :billing_phone_number, :billing_company, :billing_address1, :billing_address2, :billing_city, :billing_state, :billing_zip, :billing_country, :shipping_address1, :shipping_address2, :shipping_city, :shipping_state, :shipping_zip, :shipping_country, :shipping_phone_number, billing_address: {}, shipping_address: {}, browser_info: {})
  end

  def complete_checkout_params
    params.permit(:checkout_session_id, :transaction_token, :session_id)
  end

  def find_plan_for_checkout!
    if start_checkout_params[:checkout_session_id].present?
      Plan.find_by!(checkout_session_id: start_checkout_params[:checkout_session_id])
    elsif start_checkout_params[:plan_id].present?
      Plan.find(start_checkout_params[:plan_id])
    else
      raise ArgumentError, "Missing checkout_session_id or plan_id"
    end
  end

  def resolve_payment_method_for_checkout!(user)
    vault_token = start_checkout_params[:vault_token].presence || start_checkout_params.dig(:payment_method, :vault_token).presence
    raise ArgumentError, "Missing vault_token" if vault_token.blank?

    sync_spreedly_payment_method!(vault_token, start_checkout_params)

    payment_method = user.payment_methods.find_or_initialize_by(vault_token: vault_token)
    payment_method.assign_attributes(
      provider: payment_method.provider.presence || "Spreedly Vault",
      card_brand: start_checkout_params[:card_brand].presence || start_checkout_params.dig(:payment_method, :card_brand) || payment_method.card_brand,
      last4: start_checkout_params[:last4].presence || start_checkout_params.dig(:payment_method, :last4) || payment_method.last4,
      exp_month: start_checkout_params[:exp_month].presence || start_checkout_params.dig(:payment_method, :exp_month) || payment_method.exp_month,
      exp_year: start_checkout_params[:exp_year].presence || start_checkout_params.dig(:payment_method, :exp_year) || payment_method.exp_year,
      cardholder_name: start_checkout_params[:cardholder_name].presence || start_checkout_params.dig(:payment_method, :cardholder_name).presence || payment_method.cardholder_name.presence || "#{user.first_name} #{user.last_name}".strip.presence || "Cardholder",
      is_default: payment_method.new_record? ? user.payment_methods.blank? : payment_method.is_default,
      last_updated_via_spreedly_at: Time.current
    )
    payment_method.save!
    payment_method
  end

  def ensure_checkout_and_payment!(user, plan, payment_method)
    payment_type = plan.duration.to_i > 0 ? "down_payment" : "full_payment"
    payment = Payment.find_by(user: user, plan: plan, payment_type: payment_type)

    if payment.blank? || payment.total_payment_including_fee.blank?
      checkout_params = {
        user_id: user.id,
        plan_id: plan.id,
        vault_token: payment_method.vault_token,
        card_brand: payment_method.card_brand,
        first_installment_date: start_checkout_params[:first_installment_date]
      }
      PaymentService.new(user, plan, checkout_params, start_checkout_params[:first_installment_date]).process_checkout
      plan.update!(status: :payment_pending) unless plan.paid?
      plan.reload
      payment = Payment.find_by!(user: user, plan: plan, payment_type: payment_type)
    else
      payment.update!(payment_method: payment_method) if payment.payment_method_id != payment_method.id
    end

    payment
  end


  def normalize_transaction(transaction)
    transaction.is_a?(Hash) ? transaction : {}
  end


  def log_three_ds_event(stage, transaction, payment:, session_id:)
    tx = normalize_transaction(transaction)
    return if tx.blank?

    helper = Spreedly::ThreeDsService.new
    Rails.logger.info({
      event: "three_ds_flow",
      stage: stage,
      session_id: session_id,
      payment_id: payment&.id,
      transaction_token: tx["token"],
      state: tx["state"],
      fingerprint_required: helper.fingerprint_required?(tx),
      fingerprint_status: helper.fingerprint_status(tx),
      required_action: tx.dig("sca_authentication", "required_action"),
      authentication_status_text: helper.authentication_status_text(tx)
    }.to_json)
  end

  def sca_provider_key
    ENV["SPREEDLY_SCA_PROVIDER_KEY"].presence
  end

  def resolve_payment!(user, plan)
    payment_type = plan.duration.to_i > 0 ? "down_payment" : "full_payment"
    Payment.find_by!(user: user, plan: plan, payment_type: payment_type)
  end

  def derive_session_status(state, challenge_url, transaction = nil)
    return "succeeded" if state.to_s == "succeeded"
    return "failed" if %w[failed gateway_processing_failed scrubbed].include?(state.to_s)
    return "challenged" if challenge_url.present?
    return "challenged" if transaction.is_a?(Hash) && Spreedly::ThreeDsService.new.pending_sca_browser_step?(transaction)

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

    event_name = succeeded ? nil : GhlInboundWebhookService::PAYMENT_FAILED_EVENT
    GhlInboundWebhookWorker.perform_async(payment.id, event_name)
  end

  def sync_spreedly_payment_method!(vault_token, params)
    attributes = spreedly_payment_method_attributes(params)
    return if attributes.blank?

    Spreedly::PaymentMethodsService.new.update_payment_method(token: vault_token, **attributes)
  rescue Spreedly::Error => e
    Rails.logger.warn("Failed to sync Spreedly payment method #{vault_token}: #{e.message}")
  end

  def spreedly_payment_method_attributes(params)
    source = params.respond_to?(:to_h) ? params.to_h.deep_symbolize_keys : {}
    billing = extract_address(source, {}, :billing)
    shipping = extract_address(source, {}, :shipping)

    {
      full_name: source[:cardholder_name],
      email: source[:billing_email],
      phone_number: source[:billing_phone_number],
      company: source[:billing_company],
      address1: billing[:address1],
      address2: billing[:address2],
      city: billing[:city],
      state: billing[:state],
      zip: billing[:zip],
      country: billing[:country],
      shipping_address1: shipping[:address1],
      shipping_address2: shipping[:address2],
      shipping_city: shipping[:city],
      shipping_state: shipping[:state],
      shipping_zip: shipping[:zip],
      shipping_country: shipping[:country],
      shipping_phone_number: source[:shipping_phone_number].presence || shipping[:phone_number]
    }.compact_blank
  end

  def extract_address(source, nested, prefix)
    nested_address = nested["#{prefix}_address".to_sym].is_a?(Hash) ? nested["#{prefix}_address".to_sym] : {}
    direct_address = source["#{prefix}_address".to_sym].is_a?(Hash) ? source["#{prefix}_address".to_sym] : {}

    {
      address1: source["#{prefix}_address1".to_sym].presence || nested["#{prefix}_address1".to_sym].presence || direct_address[:address1].presence || direct_address[:line1].presence || direct_address[:street].presence || nested_address[:address1].presence || nested_address[:line1].presence || nested_address[:street].presence,
      address2: source["#{prefix}_address2".to_sym].presence || nested["#{prefix}_address2".to_sym].presence || direct_address[:address2].presence || direct_address[:line2].presence || nested_address[:address2].presence || nested_address[:line2].presence,
      city: source["#{prefix}_city".to_sym].presence || nested["#{prefix}_city".to_sym].presence || direct_address[:city].presence || nested_address[:city].presence,
      state: source["#{prefix}_state".to_sym].presence || nested["#{prefix}_state".to_sym].presence || direct_address[:state].presence || direct_address[:province].presence || direct_address[:region].presence || nested_address[:state].presence || nested_address[:province].presence || nested_address[:region].presence,
      zip: source["#{prefix}_zip".to_sym].presence || nested["#{prefix}_zip".to_sym].presence || direct_address[:zip].presence || direct_address[:postal_code].presence || nested_address[:zip].presence || nested_address[:postal_code].presence,
      country: source["#{prefix}_country".to_sym].presence || nested["#{prefix}_country".to_sym].presence || direct_address[:country].presence || direct_address[:country_code].presence || nested_address[:country].presence || nested_address[:country_code].presence,
      phone_number: direct_address[:phone_number].presence || nested_address[:phone_number].presence
    }.compact_blank
  end

  def composer_workflow_key
    ENV["SPREEDLY_WORKFLOW_KEY"].presence || ENV["SPREEDLY_COMPOSER_WORKFLOW_KEY"].presence
  end

  # Direct gateway token — used when Composer workflow is not available or misconfigured.
  # Set SPREEDLY_DIRECT_GATEWAY_TOKEN to bypass Composer and route directly to a specific gateway.
  # When Spreedly Protect is enabled and Composer is fixed, clear this env var to re-enable Composer.
  def direct_gateway_token
    # Only use direct gateway if workflow_key is absent (Composer not configured)
    return nil if composer_workflow_key.present?
    ENV["SPREEDLY_DIRECT_GATEWAY_TOKEN"].presence
  end

  # Spreedly.ThreeDS.serialize() returns a JSON string on the frontend.
  # Rails strong params strips browser_info if it arrives as a string instead of a nested hash.
  # This helper safely parses the value regardless of whether it arrives as a String or Hash.
  def parse_browser_info(value)
    return nil if value.blank?
    return value if value.is_a?(Hash)
    return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    JSON.parse(value)
  rescue JSON::ParserError
    nil
  end
end
