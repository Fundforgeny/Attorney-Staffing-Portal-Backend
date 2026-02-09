class GhlInboundWebhookWorker
  include Sidekiq::Worker

  def perform(payment_id)
    payment = Payment.find(payment_id)
    plan = payment.plan
    user = payment.user
    agreement = plan.agreement

    total_amount = plan.total_payment + plan.total_interest_amount

    payload = {
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      payment_status: "Paid",
      payment_type: payment.payment_type == "full_payment" ? "Paid in full(PIF)" : "Payment Plan",
      plan_id: plan.id,
      down_payment: plan.down_payment,
      total_amount: total_amount,
      remaining_balance: plan.remaining_balance_logic,
      financing_agreement_url: agreement&.pdf&.url,
      engagement_letter_url: agreement&.engagement_pdf&.url
    }.compact

    webhook_url = ENV["GHL_INBOUND_WEBHOOK_URL"]
    return if webhook_url.blank?

    GhlInboundWebhookService.new(webhook_url).post(payload)
  end
end
