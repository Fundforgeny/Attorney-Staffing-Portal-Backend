class GhlPlanSyncWorker
  include Sidekiq::Worker

  def perform(plan_id, event_name = nil, _request_headers = nil)
    plan = Plan.find(plan_id)
    user = plan.user
    agreement = plan.agreement

    webhook_url = GhlInboundWebhookService.resolve_webhook_url
    if webhook_url.blank?
      Rails.logger.warn("[GHL Plan Sync] Missing webhook URL, skipping plan_id=#{plan.id}")
      return :missing_webhook_url
    end

    total_amount = plan.total_payment.to_d + plan.total_interest_amount.to_d
    payment_amount = plan.payments.succeeded.sum(:total_payment_including_fee)
    status = event_name.presence || GhlInboundWebhookService.plan_created_event
    next_payment_due = plan.next_payment_at || plan.calculated_next_payment_at

    payload = {
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      payment_type: plan.payment_plan_selected? ? "Payment Plan" : "Paid in full(PIF)",
      payment_status: status,
      status: status,
      trigger: status,
      firm_name: user.firms.where.not(name: "Fund Forge").pick(:name) || user.firm&.name || user.firms.pick(:name) || "NA",
      down_payment: plan.down_payment.to_d,
      payment_amount: payment_amount,
      installment_amount: plan.monthly_payment.to_d,
      total_amount: total_amount,
      remaining_balance: plan.remaining_balance_logic,
      overdue: "paying",
      next_payment_date: next_payment_due&.in_time_zone&.strftime("%m/%d/%Y") || "NA",
      next_payment_due: next_payment_due&.in_time_zone&.iso8601,
      financing_agreement_url: agreement&.pdf&.attached? ? agreement.pdf.url : nil,
      engagement_letter_url: agreement&.engagement_pdf&.attached? ? agreement.engagement_pdf.url : nil
    }

    GhlInboundWebhookService.new(webhook_url).call(
      payload,
      context: { worker: self.class.name, plan_id: plan.id, user_id: user.id, event_name: event_name }
    )
  end
end
