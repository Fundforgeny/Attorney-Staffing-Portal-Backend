# frozen_string_literal: true

# One-time boot recovery workflow for Render deploys.
#
# This runs VaultRecoveryAutopilot automatically on production boot unless
# explicitly disabled with:
#   DISABLE_VAULT_RECOVERY_AUTOPILOT_ON_BOOT=true
#
# Safety:
#   - does not charge cards
#   - does not redact cards
#   - does not restore missing tokens automatically
#   - does not use archived cards
#   - only fixes local false-redacted flags when Spreedly confirms token is retained/cached
#
Rails.application.config.after_initialize do
  next if ENV["DISABLE_VAULT_RECOVERY_AUTOPILOT_ON_BOOT"].to_s.downcase == "true"
  next unless Rails.env.production?
  next unless defined?(Rails::Server) || Sidekiq.server?

  Thread.new do
    sleep 8
    Rails.logger.info("[VaultRecoveryAutopilot] Auto-running safe vault recovery autopilot on boot")
    VaultRecoveryAutopilot.new(apply: true).call
  rescue StandardError => e
    Rails.logger.error("[VaultRecoveryAutopilot] Boot autopilot failed: #{e.class}: #{e.message}")
  end
end
