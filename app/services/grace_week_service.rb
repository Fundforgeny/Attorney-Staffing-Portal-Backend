# GraceWeekService
#
# Manages the full grace week lifecycle:
#
#   1. request!(plan, user, reason) — client requests a grace week
#      - Finds the current overdue/upcoming installment
#      - Creates a GraceWeekRequest in :pending status
#      - Pauses auto-retries on the original payment
#
#   2. approve!(grace_week_request, admin_note) — admin approves
#      - Sets first_half_due = original due + 7 days
#      - Sets second_half_due = original due + 14 days
#      - Splits the original payment into two half-payment records
#      - Cancels retries on the original payment (covered by grace week)
#
#   3. deny!(grace_week_request, admin_note) — admin denies
#      - Resumes normal retry schedule on the original payment
#
#   4. record_half_payment!(grace_week_request) — called after a half-payment succeeds
#      - Increments halves_paid
#      - If both halves paid, marks grace week fully resolved
#
class GraceWeekService
  class Error < StandardError; end

  # ── Request ───────────────────────────────────────────────────────────────
  def self.request!(plan:, user:, reason: nil)
    raise Error, "A grace week request is already open for this plan." unless GraceWeekRequest.eligible?(plan)

    payment = find_target_payment(plan)
    raise Error, "No eligible payment found to apply a grace week to." unless payment

    half = (payment.payment_amount / 2.0).round(2)

    grace = GraceWeekRequest.create!(
      plan:         plan,
      user:         user,
      payment:      payment,
      status:       :pending,
      reason:       reason,
      half_amount:  half,
      halves_paid:  0,
      requested_at: Time.current
    )

    # Pause auto-retries while pending review
    payment.update_columns(next_retry_at: nil)

    grace
  end

  # ── Approve ───────────────────────────────────────────────────────────────
  def self.approve!(grace:, admin_note: nil)
    raise Error, "Grace week request is not pending." unless grace.pending?

    original_payment = grace.payment
    plan             = grace.plan
    user             = grace.user
    half             = grace.half_amount || (original_payment.payment_amount / 2.0).round(2)
    base_date        = (original_payment.scheduled_at || Time.current).to_date

    first_due  = base_date + 7.days
    second_due = base_date + 14.days

    ActiveRecord::Base.transaction do
      grace.update!(
        status:         :approved,
        admin_note:     admin_note,
        approved_at:    Time.current,
        half_amount:    half,
        first_half_due:  first_due,
        second_half_due: second_due
      )

      # Cancel retries on the original payment — grace week covers it
      original_payment.update_columns(
        next_retry_at:  nil,
        decline_reason: "grace_week_approved"
      )

      # Create first half-payment (pending, due in 7 days)
      plan.payments.create!(
        user:                        user,
        payment_method:              original_payment.payment_method,
        payment_type:                :monthly_payment,
        payment_amount:              half,
        transaction_fee:             (half * PaymentPlanFeeCalculator::FEE_PERCENTAGE).round(2),
        total_payment_including_fee: (half * (1 + PaymentPlanFeeCalculator::FEE_PERCENTAGE)).round(2),
        status:                      :pending,
        scheduled_at:                first_due.to_time,
        retry_count:                 0,
        grace_week_request_id:       grace.id
      )

      # Create second half-payment (pending, due in 14 days)
      plan.payments.create!(
        user:                        user,
        payment_method:              original_payment.payment_method,
        payment_type:                :monthly_payment,
        payment_amount:              half,
        transaction_fee:             (half * PaymentPlanFeeCalculator::FEE_PERCENTAGE).round(2),
        total_payment_including_fee: (half * (1 + PaymentPlanFeeCalculator::FEE_PERCENTAGE)).round(2),
        status:                      :pending,
        scheduled_at:                second_due.to_time,
        retry_count:                 0,
        grace_week_request_id:       grace.id
      )
    end

    # Notify client via GHL
    GhlInboundWebhookWorker.perform_async(
      original_payment.id,
      "grace_week_approved"
    )

    grace
  end

  # ── Deny ──────────────────────────────────────────────────────────────────
  def self.deny!(grace:, admin_note: nil)
    raise Error, "Grace week request is not pending." unless grace.pending?

    original_payment = grace.payment

    grace.update!(
      status:     :denied,
      admin_note: admin_note,
      denied_at:  Time.current
    )

    # Resume normal retry schedule — next payday at least 3 days out
    next_retry = RecurringChargeService.new(original_payment).send(:next_payday_after, Date.today + 3.days)
    original_payment.update_columns(next_retry_at: next_retry)

    # Notify client via GHL
    GhlInboundWebhookWorker.perform_async(
      original_payment.id,
      "grace_week_denied"
    )

    grace
  end

  # ── Record Half Payment ───────────────────────────────────────────────────
  def self.record_half_payment!(grace:)
    grace.increment!(:halves_paid)

    if grace.fully_paid?
      # Mark the original payment as covered
      grace.payment.update_columns(
        status:         Payment.statuses[:succeeded],
        decline_reason: "covered_by_grace_week_id_#{grace.id}",
        paid_at:        Time.current
      )
    end
  end

  # ── Private ───────────────────────────────────────────────────────────────
  def self.find_target_payment(plan)
    # Prefer the most recently failed/pending installment
    plan.payments
        .where(payment_type: [:monthly_payment, :full_payment])
        .where(status: [Payment.statuses[:pending], Payment.statuses[:processing], Payment.statuses[:failed]])
        .where.not(decline_reason: [nil, ""])
        .order(scheduled_at: :desc)
        .first ||
      plan.payments
          .where(payment_type: [:monthly_payment, :full_payment])
          .where(status: [Payment.statuses[:pending], Payment.statuses[:processing]])
          .where("scheduled_at <= ?", 3.days.from_now)
          .order(scheduled_at: :asc)
          .first
  end
  private_class_method :find_target_payment
end
