# frozen_string_literal: true

# One-time boot report for Render deploys.
#
# This report is read-only. It does not modify payment methods, payments, plans,
# Spreedly tokens, or archived/redacted states. It prints masked/count-based output
# to logs so we can determine which lost cards may be recoverable.
#
# It runs automatically on boot unless explicitly disabled with:
#   DISABLE_VAULT_RECOVERY_REPORT_ON_BOOT=true
#
Rails.application.config.after_initialize do
  next if ENV["DISABLE_VAULT_RECOVERY_REPORT_ON_BOOT"].to_s.downcase == "true"
  next unless Rails.env.production?
  next unless defined?(Rails::Server) || Sidekiq.server?

  Thread.new do
    sleep 8
    Rails.logger.info("[VaultRecoveryReporter] Auto-running read-only vault recovery report on boot")
    VaultRecoveryReporter.new.print_report
  rescue StandardError => e
    Rails.logger.error("[VaultRecoveryReporter] Boot report failed: #{e.class}: #{e.message}")
  end
end
