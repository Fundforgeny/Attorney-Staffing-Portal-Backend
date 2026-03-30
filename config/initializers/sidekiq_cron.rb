# Sidekiq-Cron scheduled jobs for GHL payment event notifications.
# These jobs scan all active plans daily and fire the appropriate GHL webhook events.
# GHL handles the actual notification send timing (e.g., waits until business hours).
#
# Note: These are separate from the login/magic-link webhook (GhlWebhookService).

Sidekiq.configure_server do |config|
  config.on(:startup) do
    Sidekiq::Cron::Job.load_from_hash(
      "ghl_7_day_reminder" => {
        "class"       => "GhlPaymentReminderWorker",
        "args"        => ["7_day_reminder"],
        "cron"        => "0 8 * * *",   # Daily at 8:00 AM UTC
        "description" => "Fire GHL 7-day payment reminder for upcoming payments"
      },
      "ghl_24_hour_reminder" => {
        "class"       => "GhlPaymentReminderWorker",
        "args"        => ["24_hour_reminder"],
        "cron"        => "0 9 * * *",   # Daily at 9:00 AM UTC
        "description" => "Fire GHL 24-hour payment reminder for payments due tomorrow"
      },
      "ghl_30_days_late" => {
        "class"       => "GhlPaymentReminderWorker",
        "args"        => ["30_days_late"],
        "cron"        => "0 10 * * *",  # Daily at 10:00 AM UTC
        "description" => "Fire GHL 30-days-late notification for overdue plans"
      }
    )
  end
end
