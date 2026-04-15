# app/workers/sync_billing_from_ghl_worker.rb
#
# Bulk-syncs billing address/email/phone from GHL for all active plan users
# who are missing one or more required Stripe Radar fields.
#
# Run once via:
#   SyncBillingFromGhlWorker.perform_async
#
# Or from Rails console:
#   SyncBillingFromGhlWorker.new.perform
#
class SyncBillingFromGhlWorker
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: 3

  def perform
    users = users_missing_billing
    Rails.logger.info("[SyncBillingFromGhl] Found #{users.count} users missing billing data")

    updated = 0
    skipped = 0

    users.each do |user|
      svc = GhlBillingSyncService.new(user)
      if svc.sync_if_needed!
        updated += 1
        Rails.logger.info("[SyncBillingFromGhl] Synced user_id=#{user.id} (#{user.email})")
      else
        skipped += 1
        Rails.logger.warn("[SyncBillingFromGhl] Could not sync user_id=#{user.id} (#{user.email}) — no GHL data available")
      end
    rescue => e
      Rails.logger.error("[SyncBillingFromGhl] Error for user_id=#{user.id}: #{e.message}")
    end

    Rails.logger.info("[SyncBillingFromGhl] Done. Updated=#{updated} Skipped=#{skipped}")
  end

  private

  # Users with at least one active (non-paid, non-cancelled) plan AND at least
  # one successful payment, who are missing any required billing field.
  def users_missing_billing
    User.joins(:plans)
        .where.not(plans: { status: [Plan.statuses[:paid], Plan.statuses[:cancelled]] })
        .where(id: Payment.where(status: :succeeded).select(:user_id))
        .where(
          "users.address_street IS NULL OR users.address_street = '' OR " \
          "users.city IS NULL OR users.city = '' OR " \
          "users.state IS NULL OR users.state = '' OR " \
          "users.postal_code IS NULL OR users.postal_code = '' OR " \
          "users.email IS NULL OR users.email = ''"
        )
        .distinct
  end
end
