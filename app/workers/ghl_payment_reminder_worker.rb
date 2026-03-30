# GhlPaymentReminderWorker
#
# Handles scheduled GHL payment notification events:
#   - 7 day reminder   : fires when next_payment_at is 7 days from today
#   - 24 hour reminder : fires when next_payment_at is 1 day from today
#   - 30 days late     : fires when next_payment_at was 30 days ago and plan is still unpaid
#   - chargeback       : fired manually or via a future chargeback webhook
#
# This worker is separate from the login/magic-link webhook (GhlWebhookService).
# It posts to the GHL payment event webhook via GhlInboundWebhookService.
#
# Scheduled via Sidekiq-Cron (see config/initializers/sidekiq_cron.rb).
# GHL handles the actual send timing — if the job fires at midnight, GHL will
# wait until business hours before sending the notification to the contact.
class GhlPaymentReminderWorker
  include Sidekiq::Worker

  SEVEN_DAY_WINDOW_DAYS    = 7
  TWENTY_FOUR_HOUR_WINDOW_DAYS = 1
  THIRTY_DAYS_LATE_DAYS    = 30

  # Called by cron — scans all active plans and fires the appropriate reminder events.
  def perform(event_type = "all")
    webhook_url = GhlInboundWebhookService.resolve_webhook_url
    if webhook_url.blank?
      Rails.logger.warn("[GHL Reminder Worker] Missing webhook URL, skipping")
      return
    end

    case event_type.to_s
    when "7_day_reminder"
      fire_upcoming_reminders(webhook_url, SEVEN_DAY_WINDOW_DAYS, GhlInboundWebhookService::SEVEN_DAY_REMINDER_EVENT)
    when "24_hour_reminder"
      fire_upcoming_reminders(webhook_url, TWENTY_FOUR_HOUR_WINDOW_DAYS, GhlInboundWebhookService::TWENTY_FOUR_HOUR_REMINDER_EVENT)
    when "30_days_late"
      fire_overdue_reminders(webhook_url)
    when "chargeback"
      # Chargeback is fired per-plan via perform_async(plan_id, "chargeback")
      # This branch is not used by the cron job
      Rails.logger.warn("[GHL Reminder Worker] Chargeback event_type called without plan_id — use GhlChargebackWorker instead")
    else
      # "all" — run all three scheduled scans
      fire_upcoming_reminders(webhook_url, SEVEN_DAY_WINDOW_DAYS, GhlInboundWebhookService::SEVEN_DAY_REMINDER_EVENT)
      fire_upcoming_reminders(webhook_url, TWENTY_FOUR_HOUR_WINDOW_DAYS, GhlInboundWebhookService::TWENTY_FOUR_HOUR_REMINDER_EVENT)
      fire_overdue_reminders(webhook_url)
    end
  end

  private

  # Fires a reminder for all active payment-plan plans whose next payment is exactly
  # `days_ahead` days from today (within a ±12h window to handle timezone drift).
  def fire_upcoming_reminders(webhook_url, days_ahead, event_name)
    target_date = days_ahead.days.from_now.to_date
    window_start = target_date.beginning_of_day
    window_end   = target_date.end_of_day

    plans = Plan.where(status: Plan.statuses[:draft])
                .where(next_payment_at: window_start..window_end)

    Rails.logger.info("[GHL Reminder Worker] #{event_name}: found #{plans.count} plans due on #{target_date}")

    plans.each do |plan|
      fire_plan_event(webhook_url, plan, event_name)
    rescue StandardError => e
      Rails.logger.error("[GHL Reminder Worker] Failed for plan_id=#{plan.id} event=#{event_name}: #{e.message}")
    end
  end

  # Fires the 30-days-late event for all plans whose next_payment_at was exactly
  # 30 days ago and are still in an unpaid/active state.
  def fire_overdue_reminders(webhook_url)
    target_date  = THIRTY_DAYS_LATE_DAYS.days.ago.to_date
    window_start = target_date.beginning_of_day
    window_end   = target_date.end_of_day

    plans = Plan.where(status: Plan.statuses[:draft])
                .where(next_payment_at: window_start..window_end)

    Rails.logger.info("[GHL Reminder Worker] 30_days_late: found #{plans.count} plans overdue since #{target_date}")

    plans.each do |plan|
      fire_plan_event(webhook_url, plan, GhlInboundWebhookService::THIRTY_DAYS_LATE_EVENT)
    rescue StandardError => e
      Rails.logger.error("[GHL Reminder Worker] Failed for plan_id=#{plan.id} event=30_days_late: #{e.message}")
    end
  end

  def fire_plan_event(webhook_url, plan, event_name)
    user      = plan.user
    agreement = plan.agreement
    next_due  = plan.next_payment_at || plan.calculated_next_payment_at
    total_amount  = plan.total_payment.to_d + plan.total_interest_amount.to_d
    last_payment  = plan.payments.succeeded.order(paid_at: :desc).first
    payment_amount = last_payment&.total_payment_including_fee.to_d || last_payment&.payment_amount.to_d || 0
    # If payment_amount == total_amount, client paid everything upfront — down_payment equals payment_amount
    down_payment  = payment_amount == total_amount ? payment_amount : plan.down_payment.to_d
    firm_name     = resolve_firm_name(user)

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
      # overdue only for the 30-days-late event; reminders (7-day, 24-hour) are still "paying"
      overdue:        event_name == GhlInboundWebhookService::THIRTY_DAYS_LATE_EVENT ? "overdue" : "paying",
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

  def resolve_firm_name(user)
    user.firms.where.not(name: "Fund Forge").pick(:name) || user.firm&.name || user.firms.pick(:name) || "NA"
  end

  def generate_magic_link(user)
    LoginLinkService.new(user: user).generate_link
  rescue StandardError => e
    Rails.logger.warn("[GHL Reminder Worker] Could not generate magic link for user_id=#{user.id}: #{e.message}")
    nil
  end

  def plan_overdue?(plan)
    due = plan.next_payment_at || plan.calculated_next_payment_at
    return false if due.nil?

    due.to_date < Time.current.to_date
  end
end
