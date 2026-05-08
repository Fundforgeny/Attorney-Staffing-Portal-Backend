# frozen_string_literal: true

# One-time cleanup for known duplicate client profiles.
#
# Safety:
#   - does not delete users
#   - does not delete plans
#   - does not charge cards
#   - does not redact cards
#   - stops duplicate active/unpaid plan recovery rows so reports do not double-count
#
class DuplicateClientProfileCleanup
  CANONICAL_USER_ID = 776
  DUPLICATE_USER_ID = 918
  DUPLICATE_PLAN_IDS = [1114].freeze
  DUPLICATE_PAYMENT_METHOD_IDS = [105, 108].freeze

  ACTIVE_PLAN_STATUSES = [
    Plan.statuses[:draft],
    Plan.statuses[:agreement_generated],
    Plan.statuses[:payment_pending]
  ].freeze

  CLEANUP_REASON = "merged_duplicate_client_profile"

  def call
    puts "\n=== Duplicate Client Profile Cleanup ==="
    puts "Generated at: #{Time.current}"
    puts "Canonical user_id=#{CANONICAL_USER_ID}"
    puts "Duplicate user_id=#{DUPLICATE_USER_ID}"
    puts "Duplicate plan IDs=#{DUPLICATE_PLAN_IDS.join(', ')}"
    puts ""

    canonical_user = User.find_by(id: CANONICAL_USER_ID)
    duplicate_user = User.find_by(id: DUPLICATE_USER_ID)

    unless canonical_user && duplicate_user
      puts "Canonical or duplicate user not found. No cleanup applied."
      return
    end

    cancelled_plan_ids = []
    stopped_payment_count = 0
    archived_card_count = 0

    ActiveRecord::Base.transaction do
      duplicate_plans.each do |plan|
        open_payments = plan.payments.where(status: [Payment.statuses[:pending], Payment.statuses[:processing], Payment.statuses[:failed]])

        stopped_payment_count += open_payments.update_all(
          status: Payment.statuses[:failed],
          needs_new_card: false,
          next_retry_at: nil,
          decline_reason: CLEANUP_REASON,
          updated_at: Time.current
        )

        plan.update_columns(
          status: Plan.statuses[:failed],
          next_payment_at: nil,
          updated_at: Time.current
        )

        cancelled_plan_ids << plan.id
        puts "cancelled_duplicate_plan_id=#{plan.id} | duplicate_user_id=#{plan.user_id}"
      end

      duplicate_payment_methods.each do |payment_method|
        payment_method.update_columns(
          archived_at: Time.current,
          is_default: false,
          updated_at: Time.current
        )
        archived_card_count += 1
        puts "archived_duplicate_pm_id=#{payment_method.id} | user_id=#{payment_method.user_id}"
      end
    end

    puts ""
    puts "Duplicate plans cancelled: #{cancelled_plan_ids.join(', ')}"
    puts "Duplicate recovery payments stopped: #{stopped_payment_count}"
    puts "Duplicate card records archived: #{archived_card_count}"
    puts "No users/cards/plans were deleted and no vault tokens were redacted."
  rescue StandardError => e
    Rails.logger.error("[DuplicateClientProfileCleanup] Failed: #{e.class}: #{e.message}")
    puts "[DuplicateClientProfileCleanup] Failed: #{e.class}: #{e.message}"
  end

  private

  def duplicate_plans
    Plan
      .where(id: DUPLICATE_PLAN_IDS, user_id: DUPLICATE_USER_ID, status: ACTIVE_PLAN_STATUSES)
      .order(:id)
  end

  def duplicate_payment_methods
    PaymentMethod.where(id: DUPLICATE_PAYMENT_METHOD_IDS, user_id: DUPLICATE_USER_ID)
  end
end
