# frozen_string_literal: true

# OneTimeOverdueChargeRun
#
# Queues a controlled one-time charge attempt for overdue active/unpaid plans.
#
# Operational model:
#   Client -> Plan -> one oldest overdue payment to attempt
#
# Safety:
#   - charges/enqueues at most one overdue payment per plan
#   - skips paid/failed/expired plans
#   - skips payments marked needs_new_card
#   - skips missing vault tokens
#   - skips locally redacted cards
#   - skips archived cards
#   - skips payments already marked by this one-time run
#   - uses ChargePaymentWorker/RecurringChargeService so hard-decline and retry
#     rules remain enforced
#
class OneTimeOverdueChargeRun
  RUN_MARKER = "queued_one_time_overdue_charge_run_20260508"
  MAX_PLANS  = 250

  ACTIVE_PLAN_STATUSES = [
    Plan.statuses[:draft],
    Plan.statuses[:agreement_generated],
    Plan.statuses[:payment_pending]
  ].freeze

  def initialize(apply: true)
    @apply = ActiveModel::Type::Boolean.new.cast(apply)
  end

  def call
    puts "\n=== One-Time Overdue Charge Run ==="
    puts "Generated at: #{Time.current}"
    puts "Mode: #{apply ? 'QUEUE_CHARGES' : 'DRY_RUN'}"
    puts ""

    rows = eligible_overdue_plan_rows

    if rows.empty?
      puts "No eligible overdue plans found."
      return
    end

    queued = 0
    rows.each do |row|
      puts line_for(row)

      next unless apply

      payment = Payment.find(row["payment_id"])
      payment.update_columns(
        decline_reason: RUN_MARKER,
        next_retry_at: Time.current,
        updated_at: Time.current
      )
      ChargePaymentWorker.perform_async(payment.id)
      queued += 1
    end

    puts ""
    puts "Eligible overdue plans found: #{rows.size}"
    puts "Charge jobs queued: #{queued}"
    puts "Run marker: #{RUN_MARKER}"
    puts ""
  rescue StandardError => e
    Rails.logger.error("[OneTimeOverdueChargeRun] Failed: #{e.class}: #{e.message}")
    puts "[OneTimeOverdueChargeRun] Failed: #{e.class}: #{e.message}"
  end

  private

  attr_reader :apply

  def eligible_overdue_plan_rows
    ActiveRecord::Base.connection.exec_query(eligible_overdue_plan_rows_sql).to_a
  end

  def active_plan_status_list
    ACTIVE_PLAN_STATUSES.join(",")
  end

  def eligible_overdue_plan_rows_sql
    <<~SQL.squish
      WITH overdue_candidates AS (
        SELECT
          payments.id AS payment_id,
          payments.user_id,
          payments.plan_id,
          payments.payment_method_id,
          payments.payment_amount,
          payments.total_payment_including_fee,
          payments.scheduled_at,
          payments.retry_count,
          ROW_NUMBER() OVER (PARTITION BY payments.plan_id ORDER BY payments.scheduled_at ASC, payments.id ASC) AS row_number
        FROM payments
        INNER JOIN plans ON plans.id = payments.plan_id
        INNER JOIN payment_methods ON payment_methods.id = payments.payment_method_id
        WHERE plans.status IN (#{active_plan_status_list})
          AND payments.payment_type = #{Payment.payment_types[:monthly_payment]}
          AND payments.status = #{Payment.statuses[:pending]}
          AND payments.needs_new_card = FALSE
          AND payments.scheduled_at < NOW()
          AND (payments.decline_reason IS NULL OR payments.decline_reason <> '#{RUN_MARKER}')
          AND payment_methods.archived_at IS NULL
          AND payment_methods.spreedly_redacted_at IS NULL
          AND payment_methods.vault_token IS NOT NULL
          AND payment_methods.vault_token <> ''
      )
      SELECT
        overdue_candidates.payment_id,
        overdue_candidates.user_id,
        COALESCE(users.first_name || ' ' || users.last_name, users.email, '') AS client_name,
        users.email,
        overdue_candidates.plan_id,
        plans.name AS plan_name,
        plans.status AS plan_status,
        overdue_candidates.payment_method_id,
        payment_methods.card_brand,
        payment_methods.last4,
        overdue_candidates.payment_amount,
        overdue_candidates.total_payment_including_fee,
        overdue_candidates.scheduled_at,
        overdue_candidates.retry_count
      FROM overdue_candidates
      INNER JOIN plans ON plans.id = overdue_candidates.plan_id
      INNER JOIN users ON users.id = overdue_candidates.user_id
      INNER JOIN payment_methods ON payment_methods.id = overdue_candidates.payment_method_id
      WHERE overdue_candidates.row_number = 1
      ORDER BY overdue_candidates.scheduled_at ASC
      LIMIT #{MAX_PLANS}
    SQL
  end

  def line_for(row)
    [
      "payment_id=#{row['payment_id']}",
      "user_id=#{row['user_id']}",
      "client=#{row['client_name']}",
      "email=#{row['email']}",
      "plan_id=#{row['plan_id']}",
      "plan_name=#{row['plan_name']}",
      "pm_id=#{row['payment_method_id']}",
      "card=#{row['card_brand']} ****#{row['last4']}",
      "amount=#{row['total_payment_including_fee'] || row['payment_amount']}",
      "scheduled_at=#{row['scheduled_at']}",
      "retry_count=#{row['retry_count']}"
    ].join(" | ")
  end
end
