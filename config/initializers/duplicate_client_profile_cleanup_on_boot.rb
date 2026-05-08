# frozen_string_literal: true

# One-time cleanup for known duplicate client profiles.
#
# Runs automatically on production boot unless disabled with:
#   DISABLE_DUPLICATE_CLIENT_PROFILE_CLEANUP_ON_BOOT=true
#
# Safe behavior:
#   - does not delete users
#   - does not delete plans
#   - does not charge cards
#   - does not redact cards
#   - archives duplicate card records and cancels duplicate active/unpaid plans
#
Rails.application.config.after_initialize do
  next if ENV["DISABLE_DUPLICATE_CLIENT_PROFILE_CLEANUP_ON_BOOT"].to_s.downcase == "true"
  next unless Rails.env.production?
  next unless defined?(Rails::Server) || Sidekiq.server?

  Thread.new do
    sleep 14
    Rails.logger.info("[DuplicateClientProfileCleanup] Auto-running duplicate client profile cleanup on boot")
    DuplicateClientProfileCleanup.new.call
  rescue StandardError => e
    Rails.logger.error("[DuplicateClientProfileCleanup] Boot cleanup failed: #{e.class}: #{e.message}")
  end
end
