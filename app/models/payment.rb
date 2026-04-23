class Payment < ApplicationRecord
  belongs_to :user
  belongs_to :payment_method
  belongs_to :plan

  after_commit :sync_plan_next_payment_at, on: %i[create update destroy]

  # When any payment succeeds (manual or automated), check if the cumulative amount
  # paid this billing period now meets or exceeds the installment amount.
  # Only then are open retries cancelled — a partial payment ($50 on a $300 installment)
  # does NOT stop retries. The retry loop continues until the full installment is collected
  # or the 28-day window expires.
  after_commit :cancel_open_retries_if_covered!, on: %i[create update], if: :succeeded?

  def self.ransackable_associations(auth_object = nil)
    %w[user plan payment_method]
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[
      id payment_type status payment_amount charge_id
      scheduled_at paid_at created_at updated_at
      total_payment_including_fee transaction_fee
      user_id plan_id payment_method_id
      retry_count last_attempt_at next_retry_at decline_reason needs_new_card
      disputed disputed_at chargeflow_alert_id chargeflow_dispute_id chargeflow_recovery
    ]
  end

  enum :status, { pending: 0, processing: 1, succeeded: 2, failed: 3 }
  enum :payment_type, { down_payment: 0, monthly_payment: 1, full_payment: 2 }

  scope :due_today,           -> { where(scheduled_at: Date.current.beginning_of_day..Date.current.end_of_day) }
  scope :needs_new_card,      -> { where(needs_new_card: true) }
  scope :retryable,           -> { where(needs_new_card: false).where("retry_count > 0").where(status: [ statuses[:pending], statuses[:processing] ]) }
  scope :due_for_retry,       -> { retryable.where("next_retry_at <= ?", Time.current.end_of_day) }
  scope :chargeflow_recovery, -> { where(chargeflow_recovery: true) }

  # ── Stop-retry logic ─────────────────────────────────────────────────────────
  #
  # Called after any payment transitions to succeeded (manual or automated).
  # Finds all other pending/processing monthly payments for the same plan whose
  # billing period overlaps this payment's paid_at date, and cancels them if
  # the total amount paid in that period already meets or exceeds the installment.
  #
  # This covers three stop conditions:
  #   1. Automated charge succeeds           → the payment itself is marked succeeded
  #   2. 28-day window expires               → handled in RecurringChargeService#exhaust_payment!
  #   3. Manual portal payment >= installment → this callback fires and cancels retries
  #
  def cancel_open_retries_if_covered!
    return unless monthly_payment? || full_payment?
    # Chargeflow recovery payments represent a disputed amount being recovered.
    # They must not cancel other pending retries when they succeed.
    return if chargeflow_recovery?
    return if plan.nil?

    installment_amount = plan.monthly_payment.to_d
    return if installment_amount <= 0

    # Determine the billing month this payment covers.
    # Use paid_at if present, fall back to scheduled_at or today.
    reference_date = (paid_at || scheduled_at || Time.current).to_date
    period_start   = reference_date.beginning_of_month
    period_end     = reference_date.end_of_month

    # Sum all succeeded payments for this plan within the billing period.
    total_paid_this_period = plan.payments
      .where(status: Payment.statuses[:succeeded])
      .where("paid_at >= ? AND paid_at <= ?", period_start, period_end)
      .sum(:total_payment_including_fee)
      .to_d

    return if total_paid_this_period < installment_amount

    # The period is covered — cancel any open retries for this billing period.
    open_retries = plan.payments
      .monthly_payment
      .where(status: [ Payment.statuses[:pending], Payment.statuses[:processing] ])
      .where.not(id: id)  # Don't cancel the payment that just succeeded
      .where("scheduled_at >= ? AND scheduled_at <= ?", period_start, period_end)

    return if open_retries.empty?

    open_retries.update_all(
      status:         Payment.statuses[:failed],
      needs_new_card: false,
      decline_reason: "covered_by_payment_id_#{id}",
      updated_at:     Time.current
    )

    Rails.logger.info(
      "[Payment] Cancelled #{open_retries.size} open retry(ies) for plan_id=#{plan_id} " \
      "period=#{period_start}..#{period_end} — covered by payment_id=#{id} " \
      "total_paid=#{total_paid_this_period} installment=#{installment_amount}"
    )
  end

  private

  def sync_plan_next_payment_at
    Plan.find_by(id: plan_id)&.refresh_next_payment_at!
  end
end
