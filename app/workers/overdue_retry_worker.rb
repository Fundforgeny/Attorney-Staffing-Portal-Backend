# OverdueRetryWorker
#
# Daily cron job (runs at 6:00 AM EST alongside ScheduledPaymentWorker).
#
# Handles ALL overdue/failed payments that have at least one active vault token —
# regardless of plan status (failed, expired, payment_pending, etc.).
#
# KEY DIFFERENCE from ScheduledPaymentWorker:
#   - ScheduledPaymentWorker handles fresh/scheduled payments on active plans
#   - OverdueRetryWorker handles backlogged failed payments on any plan status,
#     cycling through ALL of a user's vaulted cards before giving up
#
# MULTI-CARD RETRY LOGIC:
#   For each overdue payment, try every non-redacted vault token on the user's
#   account in order (most recent first). Stop as soon as one succeeds or a
#   hard decline is received. Only fire the GHL "payment failed" + "overdue"
#   webhook AFTER all cards have been exhausted — never mid-retry.
#
# CANCELLED PLAN EXCLUSION:
#   Plans in CANCELLED_PLAN_IDS are never retried or notified.
#
# WEBHOOK:
#   Fires GhlInboundWebhookWorker with "payment failed" event for each client
#   whose cards were all exhausted this run, with overdue=true.
#
class OverdueRetryWorker
  include Sidekiq::Worker
  sidekiq_options queue: :payments, retry: 1

  # Hard decline patterns — stop retrying immediately on these
  HARD_DECLINE_PATTERNS = [
    "pick up card", "pickup card", "stolen", "lost card",
    "invalid account", "account closed", "do not honor",
    "card reported", "fraudulent", "security violation",
    "card not permitted", "transaction not permitted",
    "restricted card", "revocation", "card member cancelled",
    "invalid card number", "no card record", "no such account",
    "redacted"
  ].freeze

  # Plans that have been manually cancelled — never retry or notify these
  CANCELLED_PLAN_IDS = [
    1202,  # Joseph Stidem - 3 Months Plan
    1218,  # Lizarelis Kelley - Full Payment Plan
    1222,  # Gerald Smith - Full Payment Plan
    1223,  # Lizarelis Kelley - 12 Months Plan
    1224,  # Lizarelis Kelley - 12 Months Plan
    1225,  # Lizarelis Kelley - 12 Months Plan
    1234,  # Ronney Mboche - 12 Months Plan
    1242,  # Gerald Smith - Full Payment Plan
    1243,  # Gerald Smith - Full Payment Plan
    1247,  # Gerald Smith - Full Payment Plan
    1238,  # Angela Addington - 12 Months Plan
  ].freeze

  def perform
    Rails.logger.info("[OverdueRetryWorker] Starting overdue retry run — #{Date.current}")

    # Find all overdue payments: failed status OR pending on a failed/expired plan
    # that have at least one active vault token, excluding cancelled plans
    overdue_payments = find_overdue_payments
    Rails.logger.info("[OverdueRetryWorker] Found #{overdue_payments.size} overdue payment(s)")

    # Group by user so we can try all cards per user before notifying
    by_user = overdue_payments.group_by(&:user_id)
    succeeded_user_ids = []

    # ── Phase 1: Attempt charges for ALL users first ────────────────────────────
    by_user.each do |user_id, payments|
      user = payments.first.user
      # Get all active (non-redacted) vault tokens for this user, most recent first
      active_cards = user.payment_methods
                         .where.not(vault_token: nil)
                         .where(spreedly_redacted_at: nil)
                         .order(created_at: :desc)

      next if active_cards.empty?

      # Try each payment with each card until a success or hard decline
      payments.each do |payment|
        next if payment.status == "succeeded"

        success = false

        active_cards.each do |card|
          result = attempt_charge(payment, card)

          if result[:success]
            Rails.logger.info("[OverdueRetryWorker] SUCCESS payment_id=#{payment.id} user=#{user.email} card=#{card.id}")
            succeeded_user_ids << user_id
            success = true
            break
          elsif result[:hard_decline]
            Rails.logger.info("[OverdueRetryWorker] HARD DECLINE payment_id=#{payment.id} user=#{user.email} reason=#{result[:reason]}")
            break
          else
            Rails.logger.info("[OverdueRetryWorker] Soft decline payment_id=#{payment.id} card=#{card.id} reason=#{result[:reason]} — trying next card")
          end
        end

        break if success # Payment succeeded, move to next payment for this user
      end
    end

    # ── Phase 2: Fire GHL webhooks ONLY after ALL users have been processed ─────
    # We collect all users to notify first, then fire all webhooks at the end
    # so no webhook is sent mid-run while other cards are still being tried.
    notify_users = by_user.keys - succeeded_user_ids.uniq
    Rails.logger.info("[OverdueRetryWorker] All charges complete. Notifying #{notify_users.size} user(s) via GHL webhook")

    notify_users.each do |user_id|
      payments = by_user[user_id]
      # Pick the highest-value payment to represent this user in the webhook
      representative_payment = payments.max_by { |p| p.payment_amount.to_d }
      next unless representative_payment

      GhlInboundWebhookWorker.perform_async(
        representative_payment.id,
        GhlInboundWebhookService::PAYMENT_FAILED_EVENT
      )
    end

    Rails.logger.info("[OverdueRetryWorker] Done — succeeded=#{succeeded_user_ids.uniq.size} notified=#{notify_users.size}")
  end

  private

  def find_overdue_payments
    Payment
      .joins(:plan, :user)
      .where(
        "(payments.status = ? OR (payments.status = ? AND plans.status IN (?)))",
        Payment.statuses[:failed],
        Payment.statuses[:pending],
        [Plan.statuses[:failed], Plan.statuses[:expired], Plan.statuses[:payment_pending]]
      )
      .where.not(plans: { id: CANCELLED_PLAN_IDS })
      .where(
        "EXISTS (SELECT 1 FROM payment_methods pm WHERE pm.user_id = payments.user_id AND pm.vault_token IS NOT NULL AND pm.spreedly_redacted_at IS NULL)"
      )
      .includes(:user, :payment_method, :plan)
      .order(:user_id, payment_amount: :desc)
  end

  def attempt_charge(payment, card)
    # Use RecurringChargeService but override the payment method to the specified card
    # We temporarily assign the card to the payment for the charge attempt
    original_pm_id = payment.payment_method_id
    payment.update_columns(payment_method_id: card.id) if payment.payment_method_id != card.id

    result = RecurringChargeService.new(payment).call

    # Restore original payment method if we changed it and it failed
    if !result[:success] && payment.payment_method_id != original_pm_id
      payment.update_columns(payment_method_id: original_pm_id)
    end

    decline_reason = result[:reason].to_s.downcase
    hard = HARD_DECLINE_PATTERNS.any? { |p| decline_reason.include?(p) }

    {
      success: result[:success],
      hard_decline: hard,
      reason: result[:reason]
    }
  rescue StandardError => e
    Rails.logger.error("[OverdueRetryWorker] Error charging payment_id=#{payment.id} card=#{card.id}: #{e.message}")
    { success: false, hard_decline: false, reason: e.message }
  end
end
