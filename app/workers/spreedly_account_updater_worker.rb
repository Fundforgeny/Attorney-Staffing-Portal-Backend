# SpreedlyAccountUpdaterWorker
#
# Processes an inbound Spreedly Account Updater batch callback.
# Enqueued by Webhooks::SpreedlyAccountUpdaterController when Spreedly POSTs
# an update notification to POST /webhooks/spreedly/account_updater.
#
# Spreedly Account Updater runs as a batch process (1-2x per month).
# It contacts card networks to refresh expired or re-issued card details and
# then notifies us via the configured callback URL.
#
# This worker:
#   1. Parses the Spreedly payload to extract the updated payment method token
#      and new card details (expiry, last4, storage_state).
#   2. Finds the matching local PaymentMethod by vault_token.
#   3. Updates the local record with the refreshed card details.
#   4. If the card is now valid (not redacted/closed), requeues any payments
#      that were blocked on needs_new_card so ScheduledPaymentWorker picks them up.
#   5. If the card is redacted or closed, marks all associated pending payments
#      as needs_new_card so the client is alerted to add a new card.
#
class SpreedlyAccountUpdaterWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 3

  ACTIVE_STATES   = %w[retained cached].freeze
  INACTIVE_STATES = %w[redacted closed].freeze

  def perform(raw_payload_json)
    payload = parse_payload(raw_payload_json)
    return if payload.blank?

    spreedly_pm = extract_payment_method(payload)
    return if spreedly_pm.blank?

    vault_token = spreedly_pm["token"].to_s
    return if vault_token.blank?

    payment_method = PaymentMethod.find_by(vault_token: vault_token)
    if payment_method.nil?
      Rails.logger.info("[AccountUpdater] No local PaymentMethod found for vault_token=#{vault_token} — skipping")
      return
    end

    storage_state = spreedly_pm["storage_state"].to_s
    Rails.logger.info("[AccountUpdater] Received update for payment_method_id=#{payment_method.id} state=#{storage_state}")

    if INACTIVE_STATES.include?(storage_state)
      handle_inactive_card!(payment_method, storage_state)
    else
      handle_active_card!(payment_method, spreedly_pm)
    end
  rescue StandardError => e
    Rails.logger.error("[AccountUpdater] Error processing update: #{e.class}: #{e.message}")
    raise  # Re-raise so Sidekiq retries
  end

  private

  # ── Payload parsing ───────────────────────────────────────────────────────────

  def parse_payload(raw_json)
    JSON.parse(raw_json.to_s)
  rescue JSON::ParserError => e
    Rails.logger.error("[AccountUpdater] Invalid JSON payload: #{e.message}")
    nil
  end

  # Spreedly sends either { "payment_method": {...} } or
  # { "transaction": { "payment_method": {...} } }
  def extract_payment_method(payload)
    payload.dig("payment_method") ||
      payload.dig("transaction", "payment_method")
  end

  # ── Card is active (retained/cached) — sync new details ──────────────────────

  def handle_active_card!(payment_method, spreedly_pm)
    credit_card = spreedly_pm["credit_card"] || spreedly_pm

    updates = {
      account_updater_checked_at: Time.current,
      account_updater_updated_at: Time.current,
      last_updated_via_spreedly_at: Time.current
    }
    updates[:last4]      = credit_card["last_four_digits"].to_s if credit_card["last_four_digits"].present?
    updates[:exp_month]  = credit_card["month"].to_i            if credit_card["month"].present?
    updates[:exp_year]   = credit_card["year"].to_i             if credit_card["year"].present?
    updates[:card_brand] = credit_card["card_type"]             if credit_card["card_type"].present?

    payment_method.update_columns(updates)
    Rails.logger.info("[AccountUpdater] Synced payment_method_id=#{payment_method.id} exp=#{updates[:exp_month]}/#{updates[:exp_year]} last4=#{updates[:last4]}")

    # Requeue any payments that were blocked because this card was previously declined.
    requeue_blocked_payments!(payment_method) if card_valid?(payment_method)
  end

  # ── Card is inactive (redacted/closed) — flag all pending payments ────────────

  def handle_inactive_card!(payment_method, storage_state)
    payment_method.update_columns(
      account_updater_checked_at: Time.current,
      spreedly_redacted_at: (storage_state == "redacted" ? Time.current : payment_method.spreedly_redacted_at)
    )

    Rails.logger.warn("[AccountUpdater] Card is #{storage_state} for payment_method_id=#{payment_method.id} — flagging pending payments")

    # Flag all pending/processing payments on this card as needing a new card.
    blocked = Payment
      .where(payment_method: payment_method)
      .where(status: [ Payment.statuses[:pending], Payment.statuses[:processing] ])
      .monthly_payment

    blocked.each do |payment|
      payment.update_columns(
        status:         Payment.statuses[:failed],
        needs_new_card: true,
        decline_reason: "card_#{storage_state}"
      )

      GhlInboundWebhookWorker.perform_async(
        payment.id,
        GhlInboundWebhookService::NEEDS_NEW_CARD_EVENT
      )

      Rails.logger.warn("[AccountUpdater] Flagged payment_id=#{payment.id} needs_new_card=true (card #{storage_state})")
    end
  end

  # ── Requeue blocked payments after card refresh ───────────────────────────────
  #
  # Only called when Spreedly confirms the card has been updated (retained/cached).
  # We immediately enqueue ChargePaymentWorker rather than waiting for the next
  # scheduled run, since the card is freshly confirmed valid.
  #
  def requeue_blocked_payments!(payment_method)
    blocked = Payment
      .where(payment_method: payment_method)
      .where(needs_new_card: true)
      .where(status: Payment.statuses[:failed])
      .monthly_payment

    return if blocked.empty?

    blocked.each do |payment|
      payment.update_columns(
        needs_new_card: false,
        decline_reason: nil,
        status:         Payment.statuses[:pending],
        next_retry_at:  Time.current
      )
      # Immediately enqueue the charge — don't wait for the next scheduled sweep.
      # Spreedly has confirmed the card is valid, so we charge right away.
      ChargePaymentWorker.perform_async(payment.id)
      Rails.logger.info("[AccountUpdater] Requeued payment_id=#{payment.id} for immediate charge after card refresh via Account Updater")
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  def card_valid?(payment_method)
    return false if payment_method.exp_year.blank? || payment_method.exp_month.blank?

    expiry = Date.new(payment_method.exp_year.to_i, payment_method.exp_month.to_i, 1).end_of_month
    expiry >= Date.current
  end
end
