# frozen_string_literal: true

# Optional one-time boot report for Render deploys.
#
# Enable by setting:
#   RUN_VAULT_RECOVERY_REPORT_ON_BOOT=true
#
# This report is read-only. It does not modify payment methods, payments, plans,
# Spreedly tokens, or archived/redacted states. It prints masked/count-based output
# to logs so we can determine which lost cards may be recoverable.
#
# Recommended usage:
#   1. Turn env var on.
#   2. Redeploy backend/worker.
#   3. Copy the report from Render logs.
#   4. Turn env var off again.
#
Rails.application.config.after_initialize do
  next unless ENV["RUN_VAULT_RECOVERY_REPORT_ON_BOOT"].to_s.downcase == "true"
  next unless defined?(Rails::Server) || Sidekiq.server?

  Thread.new do
    sleep 5
    Rails.logger.info("[VaultRecoveryReporter] RUN_VAULT_RECOVERY_REPORT_ON_BOOT=true — printing read-only vault recovery report")
    VaultRecoveryReporter.new.print_report
  rescue StandardError => e
    Rails.logger.error("[VaultRecoveryReporter] Boot report failed: #{e.class}: #{e.message}")
  end
end
