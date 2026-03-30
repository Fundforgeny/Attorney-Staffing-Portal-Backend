# ChargePaymentWorker
#
# Processes a single scheduled or retry payment via RecurringChargeService.
# Enqueued by ScheduledPaymentWorker for each due payment so failures are isolated.
#
# Usage:
#   ChargePaymentWorker.perform_async(payment_id)
#
class ChargePaymentWorker
  include Sidekiq::Worker

  sidekiq_options queue: :payments, retry: 2

  def perform(payment_id)
    payment = Payment.find(payment_id)

    # Guard: skip if the payment is no longer in a chargeable state.
    unless chargeable?(payment)
      Rails.logger.info("[ChargePaymentWorker] Skipping payment_id=#{payment_id} — status=#{payment.status} needs_new_card=#{payment.needs_new_card}")
      return :skipped
    end

    # Guard: skip if the plan is already paid/failed/expired.
    plan = payment.plan
    if plan.paid? || plan.failed? || plan.expired?
      Rails.logger.info("[ChargePaymentWorker] Skipping payment_id=#{payment_id} — plan status=#{plan.status}")
      return :skipped
    end

    result = RecurringChargeService.new(payment: payment).call

    Rails.logger.info("[ChargePaymentWorker] payment_id=#{payment_id} result=#{result}")
    result
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error("[ChargePaymentWorker] Payment not found: payment_id=#{payment_id}")
  end

  private

  def chargeable?(payment)
    return false if payment.needs_new_card?
    return false if payment.succeeded?

    payment.pending? || payment.processing?
  end
end
