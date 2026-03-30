# GhlChargebackWorker
#
# Fires the "chargeback" GHL payment event for a specific plan.
# Called when a chargeback is detected (e.g., via a future Spreedly webhook or admin action).
#
# Usage:
#   GhlChargebackWorker.perform_async(plan_id)
class GhlChargebackWorker
  include Sidekiq::Worker

  SEND_WINDOW_START_HOUR = 14  # 2:00 PM EST
  SEND_WINDOW_END_HOUR   = 15  # 3:00 PM EST (exclusive)
  SEND_WINDOW_TIMEZONE   = "Eastern Time (US & Canada)"

  def perform(plan_id)
    unless within_send_window?
      current_est = Time.current.in_time_zone(SEND_WINDOW_TIMEZONE)
      Rails.logger.info("[GHL Chargeback Worker] Outside 2–3 PM EST send window (current: #{current_est.strftime('%H:%M %Z')}), rescheduling plan_id=#{plan_id}")
      next_window = next_send_window_at
      self.class.perform_at(next_window, plan_id)
      return :rescheduled
    end

    plan = Plan.find(plan_id)
    user = plan.user
    agreement = plan.agreement

    webhook_url = GhlInboundWebhookService.resolve_webhook_url
    if webhook_url.blank?
      Rails.logger.warn("[GHL Chargeback Worker] Missing webhook URL, skipping plan_id=#{plan.id}")
      return
    end

    next_due      = plan.next_payment_at || plan.calculated_next_payment_at
    total_amount  = plan.total_payment.to_d + plan.total_interest_amount.to_d
    last_payment  = plan.payments.succeeded.order(paid_at: :desc).first
    payment_amount = last_payment&.total_payment_including_fee.to_d || last_payment&.payment_amount.to_d || 0
    # If payment_amount == total_amount, client paid everything upfront — down_payment equals payment_amount
    down_payment  = payment_amount == total_amount ? payment_amount : plan.down_payment.to_d
    event_name    = GhlInboundWebhookService::CHARGEBACK_EVENT
    firm_name     = user.firms.where.not(name: "Fund Forge").pick(:name) || user.firm&.name || user.firms.pick(:name) || "NA"

    payload = {
      email:          user.email.presence || "NA",
      first_name:     user.first_name.presence || "NA",
      last_name:      user.last_name.presence || "NA",
      phone:          user.phone.presence || "NA",
      payment_type:   plan.payment_plan_selected? ? "Payment Plan" : "Paid in full(PIF)",
      payment_status: event_name,
      status:         event_name,
      trigger:        event_name,
      firm_name:      firm_name,
      down_payment:        down_payment,
      payment_amount:      payment_amount,
      installment_amount:  plan.monthly_payment.to_d,
      total_amount:        total_amount,
      remaining_balance:   plan.remaining_balance_logic.to_d,
      overdue:        "overdue",
      next_payment_date: next_due&.in_time_zone&.strftime("%m/%d/%Y"),
      next_payment_due:  next_due&.in_time_zone&.iso8601,
      last_paid:         last_payment&.paid_at&.in_time_zone&.iso8601,
      date_processed:    Time.current.iso8601,
      login_magic_link:        generate_magic_link(user),
      financing_agreement_url:  agreement&.pdf&.attached? ? agreement.pdf.url : "NA",
      engagement_letter_url:    agreement&.engagement_pdf&.attached? ? agreement.engagement_pdf.url : "NA"
    }

    GhlInboundWebhookService.new(webhook_url).call(
      payload,
      context: { worker: self.class.name, plan_id: plan.id, user_id: user.id, event_name: event_name }
    )
  end

  private

  def generate_magic_link(user)
    LoginLinkService.new(user: user).generate_link
  rescue StandardError => e
    Rails.logger.warn("[GHL Chargeback Worker] Could not generate magic link for user_id=#{user.id}: #{e.message}")
    nil
  end

  # Returns true only when the current EST time is between 2:00 PM and 2:59 PM.
  def within_send_window?
    now_est = Time.current.in_time_zone(SEND_WINDOW_TIMEZONE)
    now_est.hour >= SEND_WINDOW_START_HOUR && now_est.hour < SEND_WINDOW_END_HOUR
  end

  # Returns the next 2:00 PM EST time (today if before 2 PM, tomorrow if after 2 PM).
  def next_send_window_at
    now_est = Time.current.in_time_zone(SEND_WINDOW_TIMEZONE)
    target  = now_est.change(hour: SEND_WINDOW_START_HOUR, min: 0, sec: 0)
    target  = target + 1.day if now_est >= target
    target.utc
  end
end
