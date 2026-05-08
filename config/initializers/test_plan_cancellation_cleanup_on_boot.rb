# frozen_string_literal: true

# One-time cleanup for known test plans/accounts.
#
# Runs automatically on production boot unless disabled with:
#   DISABLE_TEST_PLAN_CANCELLATION_CLEANUP_ON_BOOT=true
#
# Safe behavior:
#   - cancels only plans connected to explicit known test payment_method IDs
#   - stops pending/processing/failed recovery payments for those plans
#   - does not charge cards
#   - does not redact cards
#   - does not delete payment methods
#
Rails.application.config.after_initialize do
  next if ENV["DISABLE_TEST_PLAN_CANCELLATION_CLEANUP_ON_BOOT"].to_s.downcase == "true"
  next unless Rails.env.production?
  next unless defined?(Rails::Server) || Sidekiq.server?

  Thread.new do
    sleep 12
    Rails.logger.info("[TestPlanCancellationCleanup] Auto-running known test plan cancellation cleanup on boot")
    TestPlanCancellationCleanup.new.call
  rescue StandardError => e
    Rails.logger.error("[TestPlanCancellationCleanup] Boot cleanup failed: #{e.class}: #{e.message}")
  end
end
