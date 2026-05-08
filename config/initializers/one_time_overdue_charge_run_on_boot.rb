# frozen_string_literal: true

# One-time controlled overdue charge queue for production deploys.
#
# Runs automatically on production boot unless disabled with:
#   DISABLE_ONE_TIME_OVERDUE_CHARGE_RUN_ON_BOOT=true
#
# This queues real charge jobs only for eligible overdue active/unpaid plans with
# usable local vault tokens. It skips needs_new_card, missing-token, archived,
# redacted, paid, failed, expired, and not-yet-retryable payments.
#
Rails.application.config.after_initialize do
  next if ENV["DISABLE_ONE_TIME_OVERDUE_CHARGE_RUN_ON_BOOT"].to_s.downcase == "true"
  next unless Rails.env.production?
  next unless defined?(Rails::Server) || Sidekiq.server?

  Thread.new do
    sleep 18
    Rails.logger.info("[OneTimeOverdueChargeRun] Auto-running eligible overdue charge queue on boot")
    OneTimeOverdueChargeRun.new(apply: true).call
  rescue StandardError => e
    Rails.logger.error("[OneTimeOverdueChargeRun] Boot charge run failed: #{e.class}: #{e.message}")
  end
end
