# ScheduledPaymentWorker
#
# Daily cron job (runs at 6:00 AM EST — money hits accounts before people spend it).
# Fires every day but RecurringChargeService only schedules next_retry_at on qualifying
# paydays, so the job naturally only picks up payments on those days.
#
# Finds all monthly installment payments that are chargeable today:
#   • Fresh due:  scheduled_at <= today, retry_count = 0, status pending/processing
#   • Retry due:  next_retry_at <= today, retry_count > 0, status pending/processing
#
# Both sets are unified into a single query. There is NO attempt-count cap —
# RecurringChargeService retries on every qualifying payday within the 28-day window.
#
# Each payment is enqueued as an isolated ChargePaymentWorker job so one failure
# never blocks others.
#
class ScheduledPaymentWorker
  include Sidekiq::Worker

  sidekiq_options queue: :payments, retry: 3

  def perform
    chargeable = find_chargeable_payments

    if chargeable.empty?
      Rails.logger.info("[ScheduledPaymentWorker] No chargeable payments today (#{Date.current})")
      return
    end

    Rails.logger.info("[ScheduledPaymentWorker] Enqueueing #{chargeable.size} payment(s) for #{Date.current}")

    chargeable.each do |payment|
      ChargePaymentWorker.perform_async(payment.id)
    end
  end

  private

  # Single unified query:
  #   Fresh due  — scheduled_at is today or earlier, never attempted (retry_count = 0)
  #   Retry due  — next_retry_at is today or earlier, previously attempted (retry_count > 0)
  #
  # Both must be:
  #   • monthly_payment type
  #   • status pending or processing
  #   • needs_new_card = false
  #   • plan not paid/failed/expired
  def find_chargeable_payments
    today_end = Time.current.end_of_day

    fresh_due = Payment
      .monthly_payment
      .where(status: chargeable_statuses)
      .where(needs_new_card: false)
      .where(retry_count: 0)
      .where("scheduled_at <= ?", today_end)

    retry_due = Payment
      .monthly_payment
      .where(status: chargeable_statuses)
      .where(needs_new_card: false)
      .where("retry_count > 0")
      .where("next_retry_at <= ?", today_end)

    payment_ids = (fresh_due.pluck(:id) + retry_due.pluck(:id)).uniq

    Payment
      .where(id: payment_ids)
      .joins(:plan)
      .where.not(plans: { status: inactive_plan_statuses })
      .includes(:user, :payment_method, plan: :agreement)
      .reject { |p| billing_period_covered?(p) }
  end

  # Exclude payments whose billing month has already been covered by a succeeded
  # payment (manual or automated) totalling >= the plan's installment amount.
  # This is a safety net — Payment#cancel_open_retries_if_covered! handles the
  # primary cancellation path, but this catches any that slip through.
  def billing_period_covered?(payment)
    plan               = payment.plan
    installment_amount = plan.monthly_payment.to_d
    return false if installment_amount <= 0

    reference_date = (payment.scheduled_at || Time.current).to_date
    period_start   = reference_date.beginning_of_month
    period_end     = reference_date.end_of_month

    total_paid = plan.payments
      .where(status: Payment.statuses[:succeeded])
      .where("paid_at >= ? AND paid_at <= ?", period_start, period_end)
      .where.not(id: payment.id)
      .sum(:total_payment_including_fee)
      .to_d

    if total_paid >= installment_amount
      Rails.logger.info("[ScheduledPaymentWorker] Skipping payment_id=#{payment.id} — billing period #{period_start}..#{period_end} already covered (paid=#{total_paid} installment=#{installment_amount})")
      return true
    end

    false
  end

  def chargeable_statuses
    [ Payment.statuses[:pending], Payment.statuses[:processing] ]
  end

  def inactive_plan_statuses
    [ Plan.statuses[:paid], Plan.statuses[:failed], Plan.statuses[:expired] ]
  end
end
