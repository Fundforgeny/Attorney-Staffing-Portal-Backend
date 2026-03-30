# Sidekiq-Cron scheduled jobs for automated payments and GHL notifications.
#
# All times are in UTC. EST = UTC-5, EDT = UTC-4.
# We use UTC-5 offsets year-round so the jobs fire at consistent EST clock times
# regardless of daylight saving (Render runs UTC).
#
#   6:00 AM EST  = 11:00 AM UTC
#   2:00 PM EST  = 19:00 UTC
#   2:00 AM EST  = 07:00 UTC
#
# Job overview:
#   scheduled_payment       — daily 6 AM EST: charge all due/retry installments
#   ghl_7_day_reminder      — daily 2 PM EST: GHL alert for payments due in 7 days
#   ghl_24_hour_reminder    — daily 2 PM EST: GHL alert for payments due tomorrow
#   ghl_30_days_late        — daily 2 PM EST: GHL alert for payments 30+ days overdue
#   spreedly_account_updater — nightly 2 AM EST: sync updated card tokens from Spreedly

Sidekiq.configure_server do |config|
  config.on(:startup) do
    Sidekiq::Cron::Job.load_from_hash(
      # ── Automated recurring charge ───────────────────────────────────────────
      "scheduled_payment" => {
        "class"       => "ScheduledPaymentWorker",
        "args"        => [],
        "cron"        => "0 11 * * *",   # Daily at 6:00 AM EST (11:00 UTC)
        "description" => "Charge all due and retry installment payments via Spreedly vault"
      },

      # ── GHL payment reminders (2 PM EST = 19:00 UTC) ────────────────────────
      "ghl_7_day_reminder" => {
        "class"       => "GhlPaymentReminderWorker",
        "args"        => ["7_day_reminder"],
        "cron"        => "0 19 * * *",   # Daily at 2:00 PM EST (19:00 UTC)
        "description" => "Fire GHL 7-day payment reminder for upcoming payments"
      },
      "ghl_24_hour_reminder" => {
        "class"       => "GhlPaymentReminderWorker",
        "args"        => ["24_hour_reminder"],
        "cron"        => "5 19 * * *",   # Daily at 2:05 PM EST (19:05 UTC)
        "description" => "Fire GHL 24-hour payment reminder for payments due tomorrow"
      },
      "ghl_30_days_late" => {
        "class"       => "GhlPaymentReminderWorker",
        "args"        => ["30_days_late"],
        "cron"        => "10 19 * * *",  # Daily at 2:10 PM EST (19:10 UTC)
        "description" => "Fire GHL 30-days-late notification for overdue plans"
      },

      # NOTE: Spreedly Account Updater is event-driven via inbound webhook callback.
      # No cron job needed — Spreedly POSTs to POST /webhooks/spreedly/account_updater
      # when their batch process completes (1-2x per month).
    )
  end
end
