class GhlPlanSyncWorker
  include Sidekiq::Worker

  def perform(plan_id, _request_headers = nil)
    plan = Plan.find(plan_id)
    user = plan.user
    agreement = plan.agreement

    total_payment = plan.total_payment || 0
    total_interest = plan.total_interest_amount || 0
    total_amount = (total_payment.to_d + total_interest.to_d).to_i
    remaining_balance = plan.remaining_balance_logic.to_i
    down_payment = (plan.down_payment || 0).to_i
    payment_amount = plan.payments.succeeded.sum(:payment_amount).to_d

    # Build payload matching the exact curl structure that works with GHL:
    #   curl -X POST <url> -H "Content-Type: application/json" -d '{ ... }'
    payload = {
      email: user.email.to_s,
      first_name: user.first_name.to_s,
      last_name: user.last_name.to_s,
      payment_type: "credit_card",
      down_payment: down_payment,
      payment_amount: payment_amount.to_f,
      total_amount: total_amount,
      remaining_balance: remaining_balance,
      financing_agreement_url: agreement&.pdf&.attached? ? agreement.pdf.url : "https://example.com/financing.pdf",
      engagement_letter_url: agreement&.engagement_pdf&.attached? ? agreement.engagement_pdf.url : "https://example.com/engagement.pdf"
    }

    webhook_url = GhlInboundWebhookService.resolve_webhook_url
    if webhook_url.blank?
      Rails.logger.warn("[GHL Plan Sync] Missing webhook URL, skipping plan_id=#{plan.id}")
      return :missing_webhook_url
    end

    GhlInboundWebhookService.new(webhook_url).call(
      payload,
      context: { worker: self.class.name, plan_id: plan.id, user_id: user.id }
    )
  end
end
