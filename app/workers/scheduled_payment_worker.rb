# ScheduledPaymentWorker
#
# Daily cron job (runs at 6:00 AM EST) that finds all monthly installment payments
# that are due today or have a retry scheduled for today, and charges them via
# RecurringChargeService.
#
# Covers two queues:
#   1. Fresh due payments  — scheduled_at <= now AND status IN (pending, processing)
#   2. Retry payments      — next_retry_at <= now AND status IN (pending, processing)
#                            AND retry_count > 0 AND needs_new_card = false
#
# Each payment is processed in its own isolated Sidekiq job (ChargePaymentWorker)
# so that one failure does not block others.
#
class ScheduledPaymentWorker
  include Sidekiq::Worker

  sidekiq_options queue: :payments, retry: 3

  def perform
    due_payments   = find_due_payments
    retry_payments = find_retry_payments

    all_payments = (due_payments + retry_payments).uniq(&:id)

    if all_payments.empty?
      Rails.logger.info("[ScheduledPaymentWorker] No payments due today (#{Date.current})")
      return
    end

    Rails.logger.info("[ScheduledPaymentWorker] Processing #{all_payments.size} payment(s) on #{Date.current}")

    all_payments.each do |payment|
      ChargePaymentWorker.perform_async(payment.id)
    end
  end

  private

  def find_due_payments
    Payment
      .monthly_payment
      .where(status: [ Payment.statuses[:pending], Payment.statuses[:processing] ])
      .where(needs_new_card: false)
      .where("scheduled_at <= ?", Time.current.end_of_day)
      .where(retry_count: 0)
      .joins(:plan)
      .where.not(plans: { status: [ Plan.statuses[:paid], Plan.statuses[:failed], Plan.statuses[:expired] ] })
      .includes(:user, :payment_method, plan: :agreement)
  end

  def find_retry_payments
    Payment
      .monthly_payment
      .where(status: [ Payment.statuses[:pending], Payment.statuses[:processing] ])
      .where(needs_new_card: false)
      .where("retry_count > 0")
      .where("next_retry_at <= ?", Time.current.end_of_day)
      .joins(:plan)
      .where.not(plans: { status: [ Plan.statuses[:paid], Plan.statuses[:failed], Plan.statuses[:expired] ] })
      .includes(:user, :payment_method, plan: :agreement)
  end
end
