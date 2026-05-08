# Sidekiq-Cron scheduled jobs for automated payments and GHL notifications.
#
# All times are in UTC. EST = UTC-5, EDT = UTC-4.
# We use UTC-5 offsets year-round so the jobs fire at consistent EST clock times
# regardless of daylight saving (Render runs UTC).
#
#   6:00 AM EST  = 11:00 AM UTC
#   6:01 AM EST  = 11:01 UTC
#   2:00 PM EST  = 19:00 UTC
#   2:00 AM EST  = 07:00 UTC
#   3:30 AM EST  = 08:30 UTC
#
# Job overview:
#   scheduled_payment        — daily 6:00 AM EST: charge fresh due/retryable installments
#   overdue_retry            — daily 6:01 AM EST: retry only overdue payments explicitly due for retry today
#   ghl_7_day_reminder       — daily 2 PM EST: GHL alert for payments due in 7 days
#   ghl_24_hour_reminder     — daily 2 PM EST: GHL alert for payments due tomorrow
#   ghl_30_days_late         — daily 2 PM EST: GHL alert for payments 30+ days overdue
#   stale_vault_cleanup      — monthly 3:30 AM EST: redact truly unused vault tokens after 12 months
#
# NOTE: Spreedly Account Updater is event-driven via inbound webhook callback.
# No cron job needed — Spreedly POSTs to POST /webhooks/spreedly/account_updater
# when their batch process completes (1-2x per month).

Sidekiq.configure_server do |config|
  config.on(:startup) do
    Sidekiq::Cron::Job.load_from_hash(
      # ── Automated recurring charge ───────────────────────────────────────────
      "scheduled_payment" => {
        "class"       => "ScheduledPaymentWorker",
        "args"        => [],
        "cron"        => "0 11 * * *",   # Daily at 6:00 AM EST (11:00 UTC)
        "description" => "Charge fresh due and retryable installment payments via Spreedly vault"
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

      # ── Overdue payment retry (6:01 AM EST = 11:01 UTC) ──────────────────────
      "overdue_retry" => {
        "class"       => "OverdueRetryWorker",
        "args"        => [],
        "cron"        => "1 11 * * *",   # Daily at 6:01 AM EST (11:01 UTC)
        "description" => "Retry only overdue payments explicitly due for retry today"
      },

      # ── Stale vault cleanup (monthly 3:30 AM EST = 08:30 UTC) ────────────────
      # Redacts truly unused vault tokens only after 12 months of no successful
      # payment and no Account Updater activity. It does not run during payment
      # failures, plan failures, or normal portal card listing.
      "stale_vault_cleanup" => {
        "class"       => "StaleVaultCleanupWorker",
        "args"        => [],
        "cron"        => "30 8 1 * *",   # Monthly on the 1st at 3:30 AM EST (08:30 UTC)
        "description" => "Redact unused Spreedly vault tokens after 12 months with no successful charge or account updater activity"
      }
    )
  end
end
