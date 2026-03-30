# GhlChargebackWorker
#
# Fires the "chargeback" GHL payment event for a specific plan.
# Called when a chargeback is detected (e.g., via a future Spreedly webhook or admin action).
#
# Usage:
#   GhlChargebackWorker.perform_async(plan_id)
class GhlChargebackWorker
  include Sidekiq::Worker

  def perform(plan_id)
    plan = Plan.find(plan_id)
    user = plan.user
    agreement = plan.agreement

    webhook_url = GhlInboundWebhookService.resolve_webhook_url
    if webhook_url.blank?
      Rails.logger.warn("[GHL Chargeback Worker] Missing webhook URL, skipping plan_id=#{plan.id}")
      return
    end

    next_due     = plan.next_payment_at || plan.calculated_next_payment_at
    total_amount = plan.total_payment.to_d + plan.total_interest_amount.to_d
    last_payment = plan.payments.succeeded.order(paid_at: :desc).first
    event_name   = GhlInboundWebhookService::CHARGEBACK_EVENT

    payload = {
      email:          user.email,
      first_name:     user.first_name,
      last_name:      user.last_name,
      payment_type:   plan.payment_plan_selected? ? "Payment Plan" : "Paid in full(PIF)",
      payment_status: event_name,
      status:         event_name,
      trigger:        event_name,
      firm_name:      resolve_firm_name(user),
      firm_slug:      resolve_firm_slug(user),
      down_payment:   plan.down_payment.to_d,
      payment_amount: last_payment&.total_payment_including_fee || last_payment&.payment_amount || 0,
      installment_amount: plan.monthly_payment.to_d,
      total_amount:   total_amount,
      remaining_balance: plan.remaining_balance_logic,
      overdue:        "overdue",
      next_payment_date: next_due&.in_time_zone&.strftime("%m/%d/%Y") || "NA",
      next_payment_due:  next_due&.in_time_zone&.iso8601,
      last_paid:         last_payment&.paid_at&.in_time_zone&.iso8601,
      date_processed:    Time.current.iso8601,
      financing_agreement_url:  agreement&.pdf&.attached? ? agreement.pdf.url : nil,
      engagement_letter_url:    agreement&.engagement_pdf&.attached? ? agreement.engagement_pdf.url : nil
    }

    GhlInboundWebhookService.new(webhook_url).call(
      payload,
      context: { worker: self.class.name, plan_id: plan.id, user_id: user.id, event_name: event_name }
    )
  end

  private

  def resolve_firm_name(user)
    user.firms.where.not(name: "Fund Forge").pick(:name) || user.firm&.name || user.firms.pick(:name) || "NA"
  end

  def resolve_firm_slug(user)
    name = resolve_firm_name(user)
    name.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")
  end
end
