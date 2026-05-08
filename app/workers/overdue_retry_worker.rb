# OverdueRetryWorker
#
# Safety-first overdue retry job.
#
# This worker only retries payments that are already overdue and explicitly due
# for retry today. It does not touch upcoming scheduled payments, and it does not
# sweep every failed payment daily or cycle through every vaulted card.
#
# RecurringChargeService owns the actual retry policy:
#   - hard-decline stop rules
#   - soft-decline payday spacing
#   - max attempts
#   - needs_new_card pause state
#
class OverdueRetryWorker
  include Sidekiq::Worker
  sidekiq_options queue: :payments, retry: 1

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
    Rails.logger.info("[OverdueRetryWorker] Starting overdue-only retry run — #{Date.current}")

    overdue_retryable_payments = find_overdue_retryable_payments
    Rails.logger.info("[OverdueRetryWorker] Found #{overdue_retryable_payments.size} overdue retryable payment(s)")

    overdue_retryable_payments.each do |payment|
      result = RecurringChargeService.new(payment: payment).call

      if result[:success]
        Rails.logger.info("[OverdueRetryWorker] SUCCESS payment_id=#{payment.id} user_id=#{payment.user_id}")
      elsif result[:exhausted]
        Rails.logger.warn("[OverdueRetryWorker] EXHAUSTED payment_id=#{payment.id} user_id=#{payment.user_id} reason=#{result[:reason]}")
      elsif result[:rescheduled]
        Rails.logger.info("[OverdueRetryWorker] RESCHEDULED payment_id=#{payment.id} user_id=#{payment.user_id} next_retry=#{result[:next_retry]}")
      else
        Rails.logger.warn("[OverdueRetryWorker] NO CHANGE payment_id=#{payment.id} user_id=#{payment.user_id} reason=#{result[:reason]}")
      end
    end

    Rails.logger.info("[OverdueRetryWorker] Done — processed=#{overdue_retryable_payments.size}")
  end

  private

  def find_overdue_retryable_payments
    Payment
      .monthly_payment
      .joins(:plan, :user)
      .where(status: Payment.statuses[:pending])
      .where(needs_new_card: false)
      .where("retry_count > 0")
      .where("scheduled_at < ?", Time.current.beginning_of_day)
      .where("next_retry_at <= ?", Time.current.end_of_day)
      .where.not(plans: { id: CANCELLED_PLAN_IDS })
      .where.not(plans: { status: inactive_plan_statuses })
      .where(
        "EXISTS (SELECT 1 FROM payment_methods pm WHERE pm.user_id = payments.user_id AND pm.vault_token IS NOT NULL AND pm.spreedly_redacted_at IS NULL)"
      )
      .includes(:user, :payment_method, :plan)
      .order(:next_retry_at, :user_id)
  end

  def inactive_plan_statuses
    [Plan.statuses[:paid], Plan.statuses[:failed], Plan.statuses[:expired]]
  end
end
