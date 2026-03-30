# RecurringChargeService
#
# Handles automated recurring installment charges for active payment plans.
# Called by ScheduledPaymentWorker for each payment that is due today.
#
# RETRY LOGIC
# -----------
# Up to 3 total attempts per payment (attempt 1 = original due date, attempts 2-3 = retries).
# Retry schedule targets paydays to maximise collection success:
#   - The 1st of the month
#   - The 15th of the month
#   - Thursdays and Fridays (weekly payday)
#   - Biweekly payday dates (every other Friday from a reference anchor)
# Retries are spread across a 2-4 week window after the original due date.
# After 3 failed attempts the payment is marked permanently failed, the plan is
# flagged, and a GHL "needs new card" alert is fired.
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
  MAX_ATTEMPTS    = 3
  RETRY_WINDOW    = 28.days   # maximum days after original due date to keep retrying

  # Biweekly payday anchor — any known Friday that is a payday.
  # Adjust this date to match the most common biweekly pay cycle in your client base.
  BIWEEKLY_ANCHOR = Date.new(2024, 1, 5)  # Friday, Jan 5 2024

  def initialize(payment:)
    @payment = payment
    @plan    = payment.plan
    @user    = payment.user
    @client  = Spreedly::Client.new
  end

  # Entry point — attempt to charge the card.
  # Returns a result hash: { success: Boolean, rescheduled: Boolean, exhausted: Boolean }
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
      handle_failure!(payment_method, transaction, decline_reason)
    end
  rescue Spreedly::Error => e
    transaction = e.payload.is_a?(Hash) ? e.payload["transaction"] : nil
    decline_reason = extract_decline_reason(transaction) || e.message
    handle_failure!(nil, transaction, decline_reason)
  rescue StandardError => e
    Rails.logger.error("[RecurringCharge] Unexpected error for payment_id=#{@payment.id}: #{e.class}: #{e.message}")
    { success: false, rescheduled: false, exhausted: false, reason: e.message }
  end

  private

  attr_reader :payment, :plan, :user, :client

  # ── Payment method resolution ────────────────────────────────────────────────

  def resolve_payment_method
    # Prefer the payment method already linked to this payment row.
    pm = payment.payment_method
    return pm if pm&.vault_token.present?

    # Fall back to the user's default/most recent payment method.
    user.payment_methods.ordered_for_user.first
  end

  # ── Spreedly purchase ────────────────────────────────────────────────────────

  def attempt_purchase!(payment_method)
    amount_cents = (payment.total_payment_including_fee.to_d * 100).to_i

    payload = {
      transaction: {
        payment_method_token: payment_method.vault_token,
        amount:               amount_cents,
        currency_code:        "USD",
        retain_on_success:    false,
        description:          "Installment payment — #{plan.name}"
      }
    }

    workflow_key = ENV["SPREEDLY_WORKFLOW_KEY"].presence || ENV["SPREEDLY_COMPOSER_WORKFLOW_KEY"].presence
    payload[:transaction][:workflow_key] = workflow_key if workflow_key.present?

    # Mark the payment as processing before the network call.
    payment.update_columns(
      status:          Payment.statuses[:processing],
      last_attempt_at: Time.current
    )

    response = client.post("/transactions/purchase.json", body: payload)
    response.fetch("transaction")
  end

  # ── Success path ─────────────────────────────────────────────────────────────

  def finalize_success!(payment_method, transaction)
    payment.update!(
      status:      :succeeded,
      charge_id:   transaction["token"] || payment.charge_id,
      paid_at:     Time.current,
      decline_reason: nil,
      needs_new_card: false
    )

    plan.update!(status: :paid) if plan.remaining_balance_logic <= 0
    plan.refresh_next_payment_at!

    SyncDataToGhl.perform_async(user.id, payment.id)
    GhlInboundWebhookWorker.perform_async(
      payment.id,
      GhlInboundWebhookService::INSTALLMENT_PAYMENT_SUCCESSFUL_EVENT
    )

    Rails.logger.info("[RecurringCharge] SUCCESS payment_id=#{payment.id} plan_id=#{plan.id} amount=#{payment.total_payment_including_fee}")
  end

  # ── Failure path ─────────────────────────────────────────────────────────────

  def handle_failure!(payment_method, transaction, decline_reason)
    new_retry_count = payment.retry_count.to_i + 1
    due_date        = payment.scheduled_at || Time.current

    payment.update!(
      status:         :failed,
      retry_count:    new_retry_count,
      last_attempt_at: Time.current,
      decline_reason:  decline_reason,
      charge_id:       transaction&.dig("token") || payment.charge_id
    )

    Rails.logger.warn("[RecurringCharge] FAILED payment_id=#{payment.id} attempt=#{new_retry_count}/#{MAX_ATTEMPTS} reason=#{decline_reason}")

    if new_retry_count >= MAX_ATTEMPTS
      # All attempts exhausted — flag the payment and alert GHL.
      exhaust_payment!
      return { success: false, rescheduled: false, exhausted: true, reason: decline_reason }
    end

    # Schedule the next retry on the next payday within the retry window.
    next_date = next_payday_after(Time.current.to_date, due_date.to_date)

    if next_date.nil? || next_date > due_date.to_date + RETRY_WINDOW
      # Retry window expired — treat as exhausted.
      exhaust_payment!
      return { success: false, rescheduled: false, exhausted: true, reason: "retry_window_expired" }
    end

    payment.update!(
      status:       :pending,
      next_retry_at: next_date.to_time(:utc)
    )

    # Fire a GHL "payment failed" alert (with retry info) at 2 PM EST.
    GhlInboundWebhookWorker.perform_async(
      payment.id,
      GhlInboundWebhookService::PAYMENT_FAILED_EVENT
    )

    Rails.logger.info("[RecurringCharge] Rescheduled payment_id=#{payment.id} next_retry=#{next_date}")
    { success: false, rescheduled: true, exhausted: false, next_retry: next_date }
  end

  def exhaust_payment!
    payment.update!(
      status:         :failed,
      needs_new_card: true
    )

    # Fire GHL "needs new card" alert — this uses a special event constant.
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

  # ── Payday schedule logic ─────────────────────────────────────────────────────
  #
  # Payday dates are (in priority order):
  #   1. The 1st of the month
  #   2. The 15th of the month
  #   3. Biweekly Fridays (every 14 days from BIWEEKLY_ANCHOR)
  #   4. Any Thursday or Friday
  #
  # We look forward from `from_date` (exclusive) and return the first payday
  # that is at least 3 days away and within the retry window from `original_due`.
  #
  def next_payday_after(from_date, original_due)
    window_end = original_due + RETRY_WINDOW
    candidate  = from_date + 1

    # Minimum 3 days between attempts.
    candidate = from_date + 3 if candidate < from_date + 3

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
