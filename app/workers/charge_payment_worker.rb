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

    # Guard: skip if this billing period has already been covered by another payment
    # (e.g. a manual portal payment was made after this retry was enqueued).
    if billing_period_covered?(payment, plan)
      Rails.logger.info("[ChargePaymentWorker] Skipping payment_id=#{payment_id} — billing period already covered")
      payment.update_columns(
        status:         Payment.statuses[:failed],
        decline_reason: "covered_by_manual_payment",
        updated_at:     Time.current
      )
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

  # Returns true if the billing period for this payment has already been covered
  # by a succeeded payment (manual or automated) that meets or exceeds the installment.
  def billing_period_covered?(payment, plan)
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

    total_paid >= installment_amount
  end
end
