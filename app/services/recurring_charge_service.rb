# RecurringChargeService
#
# Handles automated recurring installment charges for active payment plans.
# Called by ChargePaymentWorker for each payment that is due or scheduled for retry.
#
# RETRY LOGIC
# -----------
# Failed-card recovery is intentionally conservative so automated retries do not
# look like card testing or repeated automated probing.
#
# Policy:
#   - Fresh scheduled payments may run on their scheduled due date.
#   - Soft-declined payments are retried only on controlled recovery paydays:
#       * 1st of the month
#       * 15th of the month
#       * the business day before the 1st/15th when that date falls on a weekend
#       * biweekly Fridays based on BIWEEKLY_ANCHOR
#   - No generic Thursday/Friday retries.
#   - Minimum 5-day gap between attempts.
#   - Maximum 4 failed attempts total for a payment, including the first failed charge.
#   - Maximum 35-day recovery window from the original due date.
#   - After the limit/window is reached, stop charging and wait for Account Updater
#     or the client to provide a new card.
#
# VAULT TOKEN HANDLING
# --------------------
# Do not clear or redact vault tokens simply because a charge failed or Spreedly
# had an API/lookup error. A vault token should stay stored for Account Updater,
# auditability, and future recovery unless Spreedly confirms the token itself is
# redacted/missing or the user/admin explicitly removes the card.
#
# HARD DECLINE HANDLING
# ---------------------
# Certain decline reasons indicate the card should not be retried and a new card
# is required immediately. These bypass the retry window and trigger needs_new_card.
# They do not delete/redact the saved vault token.
#
# ACCOUNT UPDATER
# ---------------
# Spreedly Account Updater is callback-driven. When Spreedly refreshes a card,
# it POSTs to POST /webhooks/spreedly/account_updater. That controller updates
# the local PaymentMethod and can requeue blocked payments.
#
class RecurringChargeService
  RETRY_WINDOW         = 35.days
  MIN_GAP_DAYS         = 5
  MAX_FAILURE_ATTEMPTS = 4

  BIWEEKLY_ANCHOR = Date.new(2024, 1, 5)  # Friday, Jan 5 2024

  THREE_DS_PATTERNS = [
    "3ds",
    "3d secure",
    "authentication required",
    "authentication_required",
    "sca",
    "strong customer authentication",
    "unexpected 3ds",
    "3ds authentication",
    "requires_action",
    "requires action",
  ].freeze

  HARD_DECLINE_PATTERNS = [
    "account closed",
    "closed account",
    "pick up card",
    "pickup card",
    "stolen card",
    "lost card",
    "do not honor",
    "invalid account",
    "no such account",
    "revocation",
    "card not permitted",
    "transaction not permitted",
    "restricted card",
    "security violation",
    "fraud",
    "fraudulent",
    "invalid card number",
    "no card record",
    "card member cancelled",
    "has been redacted",
    "payment method redacted",
    "redacted",
  ].freeze

  def initialize(payment:)
    @payment = payment
    @plan    = payment.plan
    @user    = payment.user
    @client  = Spreedly::Client.new
  end

  def call
    payment_method = resolve_payment_method
    unless payment_method&.vault_token.present?
      handle_no_card!("no_vault_token")
      return { success: false, rescheduled: false, exhausted: true, reason: "no_vault_token" }
    end

    if vault_token_confirmed_redacted_or_missing?(payment_method)
      Rails.logger.warn("[RecurringCharge] Vault token confirmed redacted/missing for payment_id=#{payment.id} user=#{user.email} — pausing retries without clearing token")
      handle_no_card!("vault_token_redacted_or_missing")
      return { success: false, rescheduled: false, exhausted: true, reason: "vault_token_redacted_or_missing" }
    end

    transaction = attempt_purchase!(payment_method)

    if transaction_succeeded?(transaction)
      finalize_success!(payment_method, transaction)
      { success: true, rescheduled: false, exhausted: false }
    else
      decline_reason = extract_decline_reason(transaction)
      handle_failure!(transaction, decline_reason)
    end
  rescue Spreedly::Error => e
    transaction    = e.payload.is_a?(Hash) ? e.payload["transaction"] : nil
    decline_reason = extract_decline_reason(transaction) || e.message
    handle_failure!(transaction, decline_reason)
  rescue StandardError => e
    Rails.logger.error("[RecurringCharge] Unexpected error for payment_id=#{@payment.id}: #{e.class}: #{e.message}")
    { success: false, rescheduled: false, exhausted: false, reason: e.message }
  end

  private

  attr_reader :payment, :plan, :user, :client

  def resolve_payment_method
    pm = payment.payment_method
    return pm if pm&.vault_token.present?

    user.payment_methods.ordered_for_user.first
  end

  def attempt_purchase!(payment_method)
    GhlBillingSyncService.new(user).sync_if_needed! rescue nil
    user.reload

    amount_cents = (payment.total_payment_including_fee.to_d * 100).to_i

    payload = {
      transaction: {
        payment_method_token: payment_method.vault_token,
        amount:               amount_cents,
        currency_code:        "USD",
        retain_on_success:    false,
        description:          "Installment payment — #{plan.name}",
        email:                user.email.presence,
        billing_address: {
          name:         user.full_name.presence,
          address1:     user.address_street.presence,
          city:         user.city.presence,
          state:        user.state.presence,
          zip:          user.postal_code.presence,
          country:      (user.country.presence || "US").then { |c| c.length > 2 ? country_code(c) : c }
        }.compact
      }
    }

    payload[:transaction].delete(:billing_address) if payload.dig(:transaction, :billing_address)&.empty?
    payload[:transaction].delete(:email) if payload.dig(:transaction, :email).blank?

    workflow_key = ENV["SPREEDLY_WORKFLOW_KEY"].presence || ENV["SPREEDLY_COMPOSER_WORKFLOW_KEY"].presence || "01KFECKTHBXNNDGX1A4RSDDCKJ"
    payload[:transaction][:workflow_key] = workflow_key if workflow_key.present?

    payment.update_columns(
      status:          Payment.statuses[:processing],
      last_attempt_at: Time.current
    )

    response = client.post("/transactions/purchase.json", body: payload)
    response.fetch("transaction")
  end

  def country_code(name)
    return name if name.blank? || name.length == 2
    {
      "united states" => "US", "usa" => "US", "u.s.a." => "US",
      "canada" => "CA", "united kingdom" => "GB", "uk" => "GB",
      "australia" => "AU", "mexico" => "MX"
    }.fetch(name.downcase.strip, name)
  end

  def finalize_success!(payment_method, transaction)
    payment.update!(
      status:                  :succeeded,
      charge_id:               transaction["token"] || payment.charge_id,
      processor_transaction_id: transaction["gateway_transaction_id"].presence || payment.processor_transaction_id,
      paid_at:                 Time.current,
      decline_reason:          nil,
      needs_new_card:          false,
      next_retry_at:           nil
    )

    plan.update!(status: :paid) if plan.remaining_balance_logic <= 0
    plan.refresh_next_payment_at!

    GhlInboundWebhookWorker.perform_async(
      payment.id,
      GhlInboundWebhookService::INSTALLMENT_PAYMENT_SUCCESSFUL_EVENT
    )

    Rails.logger.info("[RecurringCharge] SUCCESS payment_id=#{payment.id} plan_id=#{plan.id} amount=#{payment.total_payment_including_fee}")
  end

  def handle_failure!(transaction, decline_reason)
    new_retry_count = payment.retry_count.to_i + 1
    original_due    = (payment.scheduled_at || Time.current).to_date
    window_end      = original_due + RETRY_WINDOW

    payment.update!(
      status:                   :failed,
      retry_count:              new_retry_count,
      last_attempt_at:          Time.current,
      decline_reason:           decline_reason,
      charge_id:                transaction&.dig("token") || payment.charge_id,
      processor_transaction_id: transaction&.dig("gateway_transaction_id").presence || payment.processor_transaction_id
    )

    Rails.logger.warn("[RecurringCharge] FAILED payment_id=#{payment.id} attempt=#{new_retry_count} reason=#{decline_reason}")

    if hard_decline?(decline_reason)
      Rails.logger.warn("[RecurringCharge] HARD DECLINE payment_id=#{payment.id} — stopping automated retries without redacting saved card")
      exhaust_payment!
      return { success: false, rescheduled: false, exhausted: true, hard_decline: true, reason: decline_reason }
    end

    if new_retry_count >= MAX_FAILURE_ATTEMPTS
      Rails.logger.warn("[RecurringCharge] MAX ATTEMPTS payment_id=#{payment.id} — stopping automated retries without redacting saved card")
      exhaust_payment!
      return { success: false, rescheduled: false, exhausted: true, reason: decline_reason }
    end

    next_date = next_payday_after(Time.current.to_date, window_end)

    if next_date.nil?
      exhaust_payment!
      return { success: false, rescheduled: false, exhausted: true, reason: decline_reason }
    end

    payment.update!(
      status:        :pending,
      next_retry_at: next_date.to_time(:utc)
    )

    GhlInboundWebhookWorker.perform_async(
      payment.id,
      GhlInboundWebhookService::PAYMENT_FAILED_EVENT
    )

    Rails.logger.info("[RecurringCharge] Rescheduled payment_id=#{payment.id} next_retry=#{next_date} (attempt #{new_retry_count}, window ends #{window_end})")
    { success: false, rescheduled: true, exhausted: false, next_retry: next_date, attempt: new_retry_count }
  end

  def exhaust_payment!
    payment.update!(
      status:         :failed,
      needs_new_card: true,
      next_retry_at:  nil
    )

    GhlInboundWebhookWorker.perform_async(
      payment.id,
      GhlInboundWebhookService::NEEDS_NEW_CARD_EVENT
    )

    Rails.logger.warn("[RecurringCharge] EXHAUSTED payment_id=#{payment.id} plan_id=#{plan.id} — needs new card; vault token preserved")
  end

  def handle_no_card!(reason = "no_vault_token")
    payment.update!(
      status:         :failed,
      needs_new_card: true,
      next_retry_at:  nil,
      decline_reason: reason
    )

    GhlInboundWebhookWorker.perform_async(
      payment.id,
      GhlInboundWebhookService::NEEDS_NEW_CARD_EVENT
    )

    Rails.logger.warn("[RecurringCharge] NO USABLE CARD payment_id=#{payment.id} user=#{user.email} reason=#{reason} — GHL needs_new_card notification fired")
  end

  def vault_token_confirmed_redacted_or_missing?(payment_method)
    vault_token = payment_method.vault_token
    return false if vault_token.blank?

    response = client.get("/payment_methods/#{vault_token}.json")
    pm = response.is_a?(Hash) ? response["payment_method"] : nil

    if pm.nil?
      Rails.logger.warn("[RecurringCharge] Spreedly returned no payment_method for token=#{vault_token}; marking unusable but preserving local token")
      return true
    end

    storage_state = pm["storage_state"].to_s
    if storage_state == "redacted"
      payment_method.update_columns(spreedly_redacted_at: Time.current, updated_at: Time.current)
      return true
    end

    false
  rescue Spreedly::Error => e
    # Only confirmed missing/not-found responses should pause the payment. Generic
    # Spreedly errors/timeouts must not clear the vault token or mark the card gone.
    if spreedly_payment_method_missing?(e)
      Rails.logger.warn("[RecurringCharge] Spreedly confirmed missing token=#{vault_token}; marking unusable but preserving local token")
      return true
    end

    Rails.logger.warn("[RecurringCharge] Spreedly token lookup error for user=#{user.email}; preserving token and continuing charge attempt: #{e.message}")
    false
  rescue StandardError => e
    Rails.logger.error("[RecurringCharge] Vault token validation error for user=#{user.email}; preserving token and continuing charge attempt: #{e.class}: #{e.message}")
    false
  end

  def spreedly_payment_method_missing?(error)
    message = error.message.to_s.downcase
    return true if message.include?("unable to find the specified payment method")
    return true if message.include?("payment method not found")

    error.respond_to?(:status) && error.status.to_i == 404
  end

  def hard_decline?(reason)
    return false if reason.blank?

    normalized = reason.to_s.downcase
    return false if THREE_DS_PATTERNS.any? { |pattern| normalized.include?(pattern) }

    HARD_DECLINE_PATTERNS.any? { |pattern| normalized.include?(pattern) }
  end

  def three_ds_decline?(reason)
    return false if reason.blank?
    normalized = reason.to_s.downcase
    THREE_DS_PATTERNS.any? { |pattern| normalized.include?(pattern) }
  end

  def next_payday_after(from_date, window_end)
    candidate = from_date + MIN_GAP_DAYS

    while candidate <= window_end
      return candidate if recovery_payday?(candidate)
      candidate += 1
    end

    nil
  end

  def recovery_payday?(date)
    first_or_fifteenth_recovery_day?(date) || biweekly_friday?(date)
  end

  def first_or_fifteenth_recovery_day?(date)
    return true if [1, 15].include?(date.day) && business_day?(date)
    return false unless date.friday?

    [date + 1.day, date + 2.days].any? { |future| [1, 15].include?(future.day) }
  end

  def business_day?(date)
    !date.saturday? && !date.sunday?
  end

  def biweekly_friday?(date)
    return false unless date.friday?

    days_since_anchor = (date - BIWEEKLY_ANCHOR).to_i
    (days_since_anchor % 14).zero?
  end

  def transaction_succeeded?(transaction)
    return false if transaction.blank?

    ActiveModel::Type::Boolean.new.cast(transaction["succeeded"]) ||
      transaction["state"].to_s == "succeeded"
  end

  def extract_decline_reason(transaction)
    return nil if transaction.blank?

    transaction["message"].presence ||
      transaction.dig("gateway_specific_response_fields", "message").presence ||
      transaction["state"].presence
  end
end
