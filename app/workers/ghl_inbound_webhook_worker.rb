class GhlInboundWebhookWorker
  include Sidekiq::Worker

  def perform(payment_id, event_name = nil, _request_headers = nil)
    payment = Payment.find(payment_id)
    plan = payment.plan
    user = payment.user

    # Guard: only fire if the contact exists in our database (has email or phone)
    unless user.email.present? || user.phone.present?
      Rails.logger.warn("[GHL Payment Webhook Worker] Skipping — user has no email or phone, user_id=#{user.id}")
      return :no_contact_identity
    end

    webhook_url = GhlInboundWebhookService.resolve_webhook_url
    if webhook_url.blank?
      Rails.logger.warn("[GHL Payment Webhook Worker] Missing webhook URL, skipping payment_id=#{payment.id}")
      return :missing_webhook_url
    end

    GhlInboundWebhookService.new(webhook_url).call(
      payload_for(payment: payment, plan: plan, event_name: event_name),
      context: {
        worker: self.class.name,
        payment_id: payment.id,
        plan_id: plan.id,
        user_id: payment.user_id,
        event_name: event_name
      }
    )
  end

  private

  def payload_for(payment:, plan:, event_name:)
    user = payment.user
    agreement = plan.agreement
    total_payment = plan.total_payment.to_d
    total_interest = plan.total_interest_amount.to_d
    total_amount = total_payment + total_interest
    next_payment_due = plan.next_payment_at || plan.calculated_next_payment_at
    status = event_name.presence || GhlInboundWebhookService.default_event_for_payment(payment)
    # overdue only when payment explicitly failed — all successful payment events are "paying"
    is_overdue = status == GhlInboundWebhookService::PAYMENT_FAILED_EVENT

    payment_amount = payment.total_payment_including_fee.presence || payment.payment_amount.to_d
    # If payment_amount == total_amount, client paid everything upfront — down_payment equals payment_amount
    down_payment = payment_amount.to_d == total_amount ? payment_amount.to_d : plan.down_payment.to_d

    {
      email:          user.email.presence || "NA",
      first_name:     user.first_name.presence || "NA",
      last_name:      user.last_name.presence || "NA",
      phone:          user.phone.presence || "NA",
      payment_type:   normalized_payment_type(plan, payment),
      payment_status: status,
      status:         status,
      trigger:        status,
      firm_name:      resolve_firm_name(user),
      down_payment:        down_payment,
      payment_amount:      payment_amount,
      installment_amount:  plan.monthly_payment.to_d,
      total_amount:        total_amount,
      remaining_balance:   plan.remaining_balance_logic.to_d,
      overdue:        is_overdue ? "overdue" : "paying",
      next_payment_date: next_payment_due&.in_time_zone&.strftime("%m/%d/%Y"),
      next_payment_due:  next_payment_due&.in_time_zone&.iso8601,
      last_paid:         payment.paid_at&.in_time_zone&.iso8601,
      date_processed:    payment.paid_at&.in_time_zone&.iso8601 || Time.current.iso8601,
      login_magic_link:  generate_magic_link(user),
      financing_agreement_url: agreement&.pdf&.attached? ? agreement.pdf.url : "NA",
      engagement_letter_url:   agreement&.engagement_pdf&.attached? ? agreement.engagement_pdf.url : "NA"
    }
  end

  def normalized_payment_type(plan, payment)
    return "Paid in full(PIF)" if payment.full_payment?
    return "Payment Plan" if plan.payment_plan_selected?

    "credit_card"
  end

  def generate_magic_link(user)
    LoginLinkService.new(user: user).generate_link
  rescue StandardError => e
    Rails.logger.warn("[GHL Payment Webhook Worker] Could not generate magic link for user_id=#{user.id}: #{e.message}")
    nil
  end

  def resolve_firm_name(user)
    user.firms.where.not(name: "Fund Forge").pick(:name) || user.firm&.name || user.firms.pick(:name) || "NA"
  end

  # Returns true if the next payment due date has passed by at least 1 day (even 1 day late = overdue)
  def plan_overdue?(plan)
    due = plan.next_payment_at || plan.calculated_next_payment_at
    return false if due.nil?

    due.to_date < Time.current.to_date
  end
end
