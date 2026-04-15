# RecurringChargeService
#
# Handles automated recurring installment charges for active payment plans.
# Called by ChargePaymentWorker for each payment that is due or scheduled for retry.
#
# RETRY LOGIC
# -----------
# There is NO fixed attempt-count cap. Instead, we retry on EVERY qualifying payday
# within a 28-day window from the original due date. This means a payment can receive
# 6-10+ attempts depending on the calendar.
#
# Qualifying retry days (attempted in this order of priority, but all are hit):
#   - The 1st of the month
#   - The 15th of the month
#   - Biweekly Fridays (every 14 days from BIWEEKLY_ANCHOR)
#   - Every Thursday
#   - Every Friday
#
# Between each attempt there is a minimum 1-day gap to avoid double-charging.
# After the 28-day window expires with no success, the payment is exhausted:
#   - needs_new_card is set to true
#   - A GHL "needs new card" alert fires at 2 PM EST
#
# HARD DECLINE HANDLING
# ---------------------
# Certain decline reasons indicate the card can never be retried and a new card
# is required immediately. These bypass the 28-day retry window and trigger
# needs_new_card + GHL alert right away:
#   - Account closed / closed account
#   - Pick up card (card reported stolen/lost by issuer)
#   - Stolen card / lost card
#   - Payment method has been redacted (Spreedly deleted the vault token)
#   - Do not honor (permanent block by issuer)
#   - Invalid account / no such account
#   - Revocation of authorization
#   - Card not permitted / transaction not permitted
#   - Restricted card / security violation
#   - Fraud / fraudulent
#   - Invalid card number / no card record
#   - Card member cancelled
#
# Soft declines (insufficient funds, generic decline, etc.) still follow the
# normal 28-day retry window with payday-based rescheduling.
#
# ACCOUNT UPDATER
# ---------------
# Spreedly Account Updater runs as a batch process (1-2x/month).
# When Spreedly refreshes a card, they POST to our callback URL
# (POST /webhooks/spreedly/account_updater).
# That controller updates the local PaymentMethod and requeues any blocked payments.
# RecurringChargeService simply uses whatever vault_token is currently on file —
# no pre-charge validation or polling is needed here.
#
class RecurringChargeService
  RETRY_WINDOW    = 28.days   # Maximum days after original due date to keep retrying
  MIN_GAP_DAYS    = 1         # Minimum days between consecutive attempts

  # Biweekly payday anchor — any known Friday that is a payday.
  # Adjust this date to match the most common biweekly pay cycle in your client base.
  BIWEEKLY_ANCHOR = Date.new(2024, 1, 5)  # Friday, Jan 5 2024

  # Hard decline patterns — any decline reason matching one of these strings
  # means the card cannot be retried and needs_new_card must be set immediately.
  # Matching is case-insensitive substring search.
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
    "has been redacted",       # Spreedly: "payment method has been redacted"
    "payment method redacted",
    "redacted",
  ].freeze

  def initialize(payment:)
    @payment = payment
    @plan    = payment.plan
    @user    = payment.user
    @client  = Spreedly::Client.new
  end

  # Entry point — attempt to charge the card.
  # Returns a result hash: { success:, rescheduled:, exhausted:, reason: }
  def call
    payment_method = resolve_payment_method
    unless payment_method&.vault_token.present?
      handle_no_card!
      return { success: false, rescheduled: false, exhausted: true, reason: "no_vault_token" }
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

  # ── Payment method resolution ────────────────────────────────────────────────

  def resolve_payment_method
    pm = payment.payment_method
    return pm if pm&.vault_token.present?

    user.payment_methods.ordered_for_user.first
  end

  # ── Spreedly purchase ────────────────────────────────────────────────────────

  def attempt_purchase!(payment_method)
    # Ensure we have the latest billing data from GHL before charging.
    # This is a no-op if all required fields are already present on the user.
    GhlBillingSyncService.new(user).sync_if_needed! rescue nil
    user.reload

    amount_cents = (payment.total_payment_including_fee.to_d * 100).to_i

    payload = {
      transaction: {
        payment_method_token: payment_method.vault_token,
        amount:               amount_cents,
        currency_code:        "USD",
        retain_on_success:    false,
        description:          "Installment payment \u2014 #{plan.name}",
        # ── Stripe Radar required signals ──────────────────────────────────────
        # Passing email, name, and billing address dramatically improves fraud
        # model accuracy and prevents Radar from blocking legitimate charges.
        # See: https://docs.stripe.com/radar/optimize-risk-factors
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

    # Remove billing_address key entirely if empty (avoid sending blank hash)
    payload[:transaction].delete(:billing_address) if payload.dig(:transaction, :billing_address)&.empty?
    payload[:transaction].delete(:email) if payload.dig(:transaction, :email).blank?

    workflow_key = ENV["SPREEDLY_WORKFLOW_KEY"].presence || ENV["SPREEDLY_COMPOSER_WORKFLOW_KEY"].presence
    payload[:transaction][:workflow_key] = workflow_key if workflow_key.present?

    payment.update_columns(
      status:          Payment.statuses[:processing],
      last_attempt_at: Time.current
    )

    response = client.post("/transactions/purchase.json", body: payload)
    response.fetch("transaction")
  end

  # Convert common country names to ISO 3166-1 alpha-2 codes for Spreedly.
  def country_code(name)
    return name if name.blank? || name.length == 2
    {
      "united states" => "US", "usa" => "US", "u.s.a." => "US",
      "canada" => "CA", "united kingdom" => "GB", "uk" => "GB",
      "australia" => "AU", "mexico" => "MX"
    }.fetch(name.downcase.strip, name)
  end

  # ── Success path ─────────────────────────────────────────────────────────────

  def finalize_success!(payment_method, transaction)
    payment.update!(
      status:         :succeeded,
      charge_id:      transaction["token"] || payment.charge_id,
      paid_at:        Time.current,
      decline_reason: nil,
      needs_new_card: false
    )

    plan.update!(status: :paid) if plan.remaining_balance_logic <= 0
    plan.refresh_next_payment_at!

    GhlInboundWebhookWorker.perform_async(
      payment.id,
      GhlInboundWebhookService::INSTALLMENT_PAYMENT_SUCCESSFUL_EVENT
    )

    Rails.logger.info("[RecurringCharge] SUCCESS payment_id=#{payment.id} plan_id=#{plan.id} amount=#{payment.total_payment_including_fee}")
  end

  # ── Failure path ─────────────────────────────────────────────────────────────

  def handle_failure!(transaction, decline_reason)
    new_retry_count = payment.retry_count.to_i + 1
    original_due    = (payment.scheduled_at || Time.current).to_date
    window_end      = original_due + RETRY_WINDOW

    payment.update!(
      status:          :failed,
      retry_count:     new_retry_count,
      last_attempt_at: Time.current,
      decline_reason:  decline_reason,
      charge_id:       transaction&.dig("token") || payment.charge_id
    )

    Rails.logger.warn("[RecurringCharge] FAILED payment_id=#{payment.id} attempt=#{new_retry_count} reason=#{decline_reason}")

    # Hard declines: card cannot be retried — exhaust immediately regardless of window.
    if hard_decline?(decline_reason)
      Rails.logger.warn("[RecurringCharge] HARD DECLINE payment_id=#{payment.id} — exhausting immediately, needs new card")
      exhaust_payment!
      return { success: false, rescheduled: false, exhausted: true, hard_decline: true, reason: decline_reason }
    end

    # Find the next qualifying payday after today (minimum 1-day gap).
    next_date = next_payday_after(Time.current.to_date, window_end)

    if next_date.nil?
      exhaust_payment!
      return { success: false, rescheduled: false, exhausted: true, reason: decline_reason }
    end

    payment.update!(
      status:        :pending,
      next_retry_at: next_date.to_time(:utc)
    )

    # Fire GHL "payment failed" alert at 2 PM EST.
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
      needs_new_card: true
    )

    GhlInboundWebhookWorker.perform_async(
      payment.id,
      GhlInboundWebhookService::NEEDS_NEW_CARD_EVENT
    )

    Rails.logger.warn("[RecurringCharge] EXHAUSTED payment_id=#{payment.id} plan_id=#{plan.id} — needs new card")
  end

  def handle_no_card!
    payment.update!(
      status:         :failed,
      needs_new_card: true,
      decline_reason: "no_vault_token"
    )

    GhlInboundWebhookWorker.perform_async(
      payment.id,
      GhlInboundWebhookService::NEEDS_NEW_CARD_EVENT
    )
  end

  # ── Hard decline detection ────────────────────────────────────────────────────

  # Returns true if the decline reason indicates the card can never be retried.
  def hard_decline?(reason)
    return false if reason.blank?

    normalized = reason.to_s.downcase
    HARD_DECLINE_PATTERNS.any? { |pattern| normalized.include?(pattern) }
  end

  # ── Payday schedule logic ─────────────────────────────────────────────────────
  #
  # Returns the next qualifying payday strictly after `from_date` (with a minimum
  # MIN_GAP_DAYS gap) that falls on or before `window_end`.
  #
  # Qualifying days — ALL of the following are attempted, not just the first match:
  #   • 1st of the month
  #   • 15th of the month
  #   • Biweekly Fridays (every 14 days from BIWEEKLY_ANCHOR)
  #   • Every Thursday
  #   • Every Friday
  #
  def next_payday_after(from_date, window_end)
    candidate = from_date + MIN_GAP_DAYS

    while candidate <= window_end
      return candidate if payday?(candidate)
      candidate += 1
    end

    nil
  end

  def payday?(date)
    return true if date.day == 1
    return true if date.day == 15
    return true if biweekly_friday?(date)
    return true if date.wday == 4  # Thursday
    return true if date.wday == 5  # Friday

    false
  end

  def biweekly_friday?(date)
    return false unless date.wday == 5  # Must be a Friday

    days_since_anchor = (date - BIWEEKLY_ANCHOR).to_i
    (days_since_anchor % 14).zero?
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

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
