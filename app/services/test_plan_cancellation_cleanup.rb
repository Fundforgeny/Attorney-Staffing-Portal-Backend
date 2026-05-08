# frozen_string_literal: true

# One-time cleanup for known test accounts/plans.
#
# This service cancels only plans connected to the explicit test payment_method IDs
# listed below. It does not charge cards, redact cards, or delete cards.
#
class TestPlanCancellationCleanup
  TEST_PAYMENT_METHOD_IDS = [103, 107, 109, 110, 111].freeze

  ACTIVE_PLAN_STATUSES = [
    Plan.statuses[:draft],
    Plan.statuses[:agreement_generated],
    Plan.statuses[:payment_pending]
  ].freeze

  CANCELLATION_REASON = "cancelled_test_account_cleanup"

  def call
    puts "\n=== Test Plan Cancellation Cleanup ==="
    puts "Generated at: #{Time.current}"
    puts "Payment method IDs: #{TEST_PAYMENT_METHOD_IDS.join(', ')}"
    puts ""

    plans = target_plans

    if plans.empty?
      puts "No active/unpaid test plans found for cancellation."
      return
    end

    cancelled_plan_ids = []
    cancelled_payment_count = 0

    Plan.transaction do
      plans.each do |plan|
        open_payments = plan.payments.where(status: [Payment.statuses[:pending], Payment.statuses[:processing], Payment.statuses[:failed]])

        updated_payments = open_payments.update_all(
          status: Payment.statuses[:failed],
          needs_new_card: false,
          next_retry_at: nil,
          decline_reason: CANCELLATION_REASON,
          updated_at: Time.current
        )

        plan.update_columns(
          status: Plan.statuses[:failed],
          next_payment_at: nil,
          updated_at: Time.current
        )

        cancelled_plan_ids << plan.id
        cancelled_payment_count += updated_payments

        puts [
          "cancelled_plan_id=#{plan.id}",
          "user_id=#{plan.user_id}",
          "plan_name=#{plan.name}",
          "payments_stopped=#{updated_payments}"
        ].join(" | ")
      end
    end

    puts ""
    puts "Cancelled plans: #{cancelled_plan_ids.join(', ')}"
    puts "Stopped payments: #{cancelled_payment_count}"
    puts "Vault tokens/cards were not redacted, deleted, or charged."
  rescue StandardError => e
    Rails.logger.error("[TestPlanCancellationCleanup] Failed: #{e.class}: #{e.message}")
    puts "[TestPlanCancellationCleanup] Failed: #{e.class}: #{e.message}"
  end

  private

  def target_plans
    Plan
      .joins(:payments)
      .where(status: ACTIVE_PLAN_STATUSES)
      .where(payments: { payment_method_id: TEST_PAYMENT_METHOD_IDS })
      .distinct
      .order(:id)
  end
end
