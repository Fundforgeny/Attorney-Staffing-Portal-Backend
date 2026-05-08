# StaleVaultCleanupWorker
#
# Redacts truly unused Spreedly vault tokens on a conservative schedule.
#
# Policy:
#   - Do not redact/delete cards because a payment failed.
#   - Do not redact/delete cards because a plan failed or did not complete.
#   - Do not run cleanup from normal portal reads/listing.
#   - Only redact cards that have been unused for at least 12 months.
#
# A card is eligible only when all of the following are true:
#   - it has a vault_token
#   - it is not already marked redacted locally
#   - it has no successful payment in the last 12 months
#   - it has no Account Updater activity in the last 12 months
#   - it is not attached to any pending/processing payment
#
# Six months may be acceptable in some lower-risk businesses, but 12 months is
# safer here because legal-financing payment plans, recoveries, disputes, and
# account-updater cycles can run long.
#
class StaleVaultCleanupWorker
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: 1

  RETENTION_PERIOD = 12.months
  BATCH_SIZE       = 100

  def perform
    cutoff = Time.current - RETENTION_PERIOD
    Rails.logger.info("[StaleVaultCleanup] Starting stale vault cleanup cutoff=#{cutoff}")

    processed = 0
    redacted  = 0
    skipped   = 0
    service   = Spreedly::PaymentMethodsService.new

    eligible_payment_methods.find_each(batch_size: BATCH_SIZE) do |payment_method|
      processed += 1

      unless stale_for_cleanup?(payment_method, cutoff)
        skipped += 1
        next
      end

      begin
        service.redact_payment_method(token: payment_method.vault_token)
        payment_method.update_columns(
          spreedly_redacted_at: Time.current,
          updated_at: Time.current
        )
        redacted += 1
        Rails.logger.info("[StaleVaultCleanup] Redacted stale payment_method_id=#{payment_method.id} user_id=#{payment_method.user_id}")
      rescue Spreedly::Error => e
        if spreedly_payment_method_missing?(e)
          payment_method.update_columns(
            spreedly_redacted_at: Time.current,
            updated_at: Time.current
          )
          redacted += 1
          Rails.logger.warn("[StaleVaultCleanup] Marked already-missing payment_method_id=#{payment_method.id} as redacted")
        else
          skipped += 1
          Rails.logger.warn("[StaleVaultCleanup] Spreedly redact failed payment_method_id=#{payment_method.id}: #{e.message}")
        end
      rescue StandardError => e
        skipped += 1
        Rails.logger.warn("[StaleVaultCleanup] Unexpected cleanup error payment_method_id=#{payment_method.id}: #{e.class}: #{e.message}")
      end
    end

    Rails.logger.info("[StaleVaultCleanup] Done processed=#{processed} redacted=#{redacted} skipped=#{skipped}")
  end

  private

  def eligible_payment_methods
    PaymentMethod
      .where.not(vault_token: [nil, ""])
      .where(spreedly_redacted_at: nil)
  end

  def stale_for_cleanup?(payment_method, cutoff)
    return false if recent_successful_payment?(payment_method, cutoff)
    return false if recent_account_updater_activity?(payment_method, cutoff)
    return false if active_payment_depends_on_card?(payment_method)

    # If the card was created or updated recently, give it the full retention window
    # even if no successful payment has occurred yet.
    last_local_activity = [payment_method.created_at, payment_method.updated_at, payment_method.last_updated_via_spreedly_at].compact.max
    return false if last_local_activity.present? && last_local_activity > cutoff

    true
  end

  def recent_successful_payment?(payment_method, cutoff)
    Payment
      .where(payment_method_id: payment_method.id)
      .where(status: Payment.statuses[:succeeded])
      .where("paid_at >= ?", cutoff)
      .exists?
  end

  def recent_account_updater_activity?(payment_method, cutoff)
    [
      payment_method.account_updater_checked_at,
      payment_method.account_updater_updated_at,
      payment_method.last_updated_via_spreedly_at
    ].compact.any? { |timestamp| timestamp >= cutoff }
  end

  def active_payment_depends_on_card?(payment_method)
    Payment
      .where(payment_method_id: payment_method.id)
      .where(status: [Payment.statuses[:pending], Payment.statuses[:processing]])
      .exists?
  end

  def spreedly_payment_method_missing?(error)
    message = error.message.to_s.downcase
    return true if message.include?("unable to find the specified payment method")
    return true if message.include?("payment method not found")

    error.respond_to?(:status) && error.status.to_i == 404
  end
end
