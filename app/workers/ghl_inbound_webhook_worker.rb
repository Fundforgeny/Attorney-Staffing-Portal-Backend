class GhlInboundWebhookWorker
  include Sidekiq::Worker

  def perform(payment_id, event_name = nil, _request_headers = nil)
    payment = Payment.find(payment_id)
    plan = payment.plan

    webhook_url = GhlInboundWebhookService.resolve_webhook_url
    if webhook_url.blank?
      Rails.logger.warn("[GHL Inbound Webhook Worker] Missing webhook URL, skipping payment_id=#{payment.id}")
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

    {
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      payment_type: normalized_payment_type(plan, payment),
      payment_status: status,
      status: status,
      trigger: status,
      firm_name: resolve_firm_name(user),
      down_payment: plan.down_payment.to_d,
      payment_amount: payment.total_payment_including_fee || payment.payment_amount,
      total_amount: total_amount,
      remaining_balance: plan.remaining_balance_logic,
      next_payment_due: next_payment_due&.in_time_zone&.iso8601,
      financing_agreement_url: agreement&.pdf&.attached? ? agreement.pdf.url : nil,
      engagement_letter_url: agreement&.engagement_pdf&.attached? ? agreement.engagement_pdf.url : nil
    }
  end

  def normalized_payment_type(plan, payment)
    return "Paid in full(PIF)" if payment.full_payment?
    return "Payment Plan" if plan.payment_plan_selected?

    "credit_card"
  end

  def resolve_firm_name(user)
    user.firms.where.not(name: "Fund Forge").pick(:name) || user.firm&.name || user.firms.pick(:name) || "NA"
  end
end
