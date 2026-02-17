class GhlInboundWebhookWorker
  include Sidekiq::Worker

  def perform(payment_id, _request_headers = nil)
    payment = Payment.find(payment_id)
    plan = payment.plan
    user = payment.user
    agreement = plan.agreement

    total_payment = plan.total_payment || 0
    total_interest = plan.total_interest_amount || 0
    total_amount = (total_payment.to_d + total_interest.to_d).to_i
    remaining_balance = plan.remaining_balance_logic.to_i
    down_payment = (plan.down_payment || 0).to_i

    # Build payload matching the exact curl structure that works with GHL
    payload = {
  email: user.email,
  first_name: user.first_name,
  last_name: user.last_name,
  payment_type: "credit_card",
  down_payment: down_payment,
  total_amount: total_amount,
  remaining_balance: remaining_balance,
  financing_agreement_url: agreement&.pdf&.attached? ? agreement.pdf.url : nil,
  engagement_letter_url: agreement&.engagement_pdf&.attached? ? agreement.engagement_pdf.url : nil
}.compact


    webhook_url = GhlInboundWebhookService.resolve_webhook_url
    if webhook_url.blank?
      Rails.logger.warn("[GHL Inbound Webhook Worker] Missing webhook URL, skipping payment_id=#{payment.id}")
      return :missing_webhook_url
    end

    GhlInboundWebhookService.new(webhook_url).call(
      payload,
      context: { worker: self.class.name, payment_id: payment.id, plan_id: plan.id, user_id: user.id }
    )
  end
end
