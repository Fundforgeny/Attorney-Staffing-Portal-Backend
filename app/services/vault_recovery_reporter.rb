# frozen_string_literal: true

# Read-only reporter for understanding which saved cards may be recoverable.
#
# This service intentionally does not modify any records and does not print full
# vault tokens or raw Spreedly transaction payloads. It is safe to run from Render
# logs or manually via rake task.
#
class VaultRecoveryReporter
  MAX_REVIEW_ROWS = 100

  ACTIVE_PLAN_STATUSES = [
    Plan.statuses[:draft],
    Plan.statuses[:agreement_generated],
    Plan.statuses[:payment_pending]
  ].freeze

  def print_report
    puts "\n=== Fund Forge Vault Recovery Report ==="
    puts "Generated at: #{Time.current}"
    puts "Environment: #{Rails.env}"
    puts ""

    print_payment_method_summary
    print_payment_recovery_summary
    print_recoverability_buckets
    print_action_list
    print_notes
  rescue StandardError => e
    Rails.logger.error("[VaultRecoveryReporter] Failed: #{e.class}: #{e.message}")
    puts "[VaultRecoveryReporter] Failed: #{e.class}: #{e.message}"
  end

  private

  def print_payment_method_summary
    token_present_scope = PaymentMethod.where.not(vault_token: [nil, ""])
    token_missing_scope = PaymentMethod.where(vault_token: [nil, ""])
    archived_scope      = PaymentMethod.where.not(archived_at: nil)
    active_scope        = PaymentMethod.where(archived_at: nil)
    redacted_scope      = PaymentMethod.where.not(spreedly_redacted_at: nil)

    puts "--- Payment Method Summary ---"
    puts "Total payment methods:                 #{PaymentMethod.count}"
    puts "Active local cards:                    #{active_scope.count}"
    puts "Archived local cards:                  #{archived_scope.count}"
    puts "With vault_token present:              #{token_present_scope.count}"
    puts "Missing vault_token locally:           #{token_missing_scope.count}"
    puts "Marked redacted locally:               #{redacted_scope.count}"
    puts "Archived + token present recoverable:  #{archived_scope.where.not(vault_token: [nil, ""]).count}"
    puts "Archived + token missing:              #{archived_scope.where(vault_token: [nil, ""]).count}"
    puts ""
  end

  def print_payment_recovery_summary
    puts "--- Payment Recovery Summary ---"
    puts "All payments needing new card:                         #{Payment.where(needs_new_card: true).count}"
    puts "All monthly payments needing new card:                 #{monthly_payment_scope.where(needs_new_card: true).count}"
    puts "Active unpaid monthly payments needing card:           #{active_unpaid_needs_card_scope.count}"
    puts "Distinct active unpaid clients needing card recovery:  #{active_unpaid_needs_card_scope.distinct.count(:user_id)}"
    puts ""
  end

  def print_recoverability_buckets
    puts "--- Active Unpaid Recoverability Buckets: Distinct Clients ---"
    puts "A) Retry candidate: active card with token, not redacted:      #{bucket_count(active_with_token_sql)}"
    puts "B) Archived card with token; requires express reactivation:    #{bucket_count(archived_with_token_sql)}"
    puts "C) Local card exists but token missing; search backups/logs:   #{bucket_count(local_card_no_token_sql)}"
    puts "D) Card marked redacted; likely client must re-enter card:     #{bucket_count(local_redacted_sql)}"
    puts "E) No local payment method record:                             #{bucket_count(no_local_payment_method_sql)}"
    puts ""
  end

  def print_action_list
    puts "--- Active Unpaid Action List: Grouped by Client/Card ---"
    rows = ActiveRecord::Base.connection.exec_query(action_list_sql).to_a

    if rows.empty?
      puts "No active unpaid recovery targets found."
      puts ""
      return
    end

    rows.each do |row|
      puts [
        "bucket=#{row['bucket']}",
        "user_id=#{row['user_id']}",
        "client=#{row['client_name']}",
        "email=#{row['email']}",
        "plan_ids=#{row['plan_ids']}",
        "payment_count=#{row['payment_count']}",
        "total_amount=#{row['total_amount']}",
        "pm_id=#{row['payment_method_id'] || 'none'}",
        "card=#{row['card_brand']} ****#{row['last4']}",
        "token_present=#{row['token_present']}",
        "archived=#{row['archived']}",
        "redacted=#{row['redacted']}",
        "last_decline=#{sanitize_decline_reason(row['last_decline_reason'])}"
      ].join(" | ")
    end
    puts ""
  end

  def print_notes
    puts "--- Notes ---"
    puts "This action list only includes active/unpaid plans: draft, agreement_generated, or payment_pending."
    puts "Retry candidates still require policy review before charging; do not blindly retry card tokens."
    puts "Archived cards with tokens are intentionally preserved but must not be charged unless expressly reactivated/permitted."
    puts "Cards missing local vault_token may still be recoverable only if the token exists in a DB backup, logs, or Spreedly transaction history."
    puts "Cards actually redacted in Spreedly are generally not recoverable and require the client to re-enter card details."
    puts ""
  end

  def monthly_payment_scope
    Payment.respond_to?(:monthly_payment) ? Payment.monthly_payment : Payment.where(payment_type: Payment.payment_types[:monthly_payment])
  end

  def active_unpaid_needs_card_scope
    monthly_payment_scope
      .joins(:plan)
      .where(needs_new_card: true)
      .where(plans: { status: ACTIVE_PLAN_STATUSES })
  end

  def sanitize_decline_reason(reason)
    return "" if reason.blank?

    text = reason.to_s
    return "no_vault_token" if text == "no_vault_token"
    return "payment method redacted" if text.downcase.include?("payment method has been redacted")
    return "gateway_processing_failed" if text.downcase.include?("gateway_processing_failed")

    text.gsub(/01[A-Z0-9]{20,}/, "[token-redacted]").truncate(120)
  end

  def bucket_count(sql)
    ActiveRecord::Base.connection.exec_query(sql).first.fetch("count").to_i
  end

  def active_plan_status_list
    ACTIVE_PLAN_STATUSES.join(",")
  end

  def active_target_where_sql
    <<~SQL.squish
      payments.needs_new_card = TRUE
      AND payments.payment_type = #{Payment.payment_types[:monthly_payment]}
      AND plans.status IN (#{active_plan_status_list})
    SQL
  end

  def active_with_token_sql
    <<~SQL.squish
      SELECT COUNT(DISTINCT payments.user_id) AS count
      FROM payments
      INNER JOIN plans ON plans.id = payments.plan_id
      INNER JOIN payment_methods ON payment_methods.user_id = payments.user_id
      WHERE #{active_target_where_sql}
        AND payment_methods.archived_at IS NULL
        AND payment_methods.spreedly_redacted_at IS NULL
        AND payment_methods.vault_token IS NOT NULL
        AND payment_methods.vault_token <> ''
    SQL
  end

  def archived_with_token_sql
    <<~SQL.squish
      SELECT COUNT(DISTINCT payments.user_id) AS count
      FROM payments
      INNER JOIN plans ON plans.id = payments.plan_id
      INNER JOIN payment_methods ON payment_methods.user_id = payments.user_id
      WHERE #{active_target_where_sql}
        AND payment_methods.archived_at IS NOT NULL
        AND payment_methods.spreedly_redacted_at IS NULL
        AND payment_methods.vault_token IS NOT NULL
        AND payment_methods.vault_token <> ''
    SQL
  end

  def local_card_no_token_sql
    <<~SQL.squish
      SELECT COUNT(DISTINCT payments.user_id) AS count
      FROM payments
      INNER JOIN plans ON plans.id = payments.plan_id
      INNER JOIN payment_methods ON payment_methods.user_id = payments.user_id
      WHERE #{active_target_where_sql}
        AND payment_methods.spreedly_redacted_at IS NULL
        AND (payment_methods.vault_token IS NULL OR payment_methods.vault_token = '')
    SQL
  end

  def local_redacted_sql
    <<~SQL.squish
      SELECT COUNT(DISTINCT payments.user_id) AS count
      FROM payments
      INNER JOIN plans ON plans.id = payments.plan_id
      INNER JOIN payment_methods ON payment_methods.user_id = payments.user_id
      WHERE #{active_target_where_sql}
        AND payment_methods.spreedly_redacted_at IS NOT NULL
    SQL
  end

  def no_local_payment_method_sql
    <<~SQL.squish
      SELECT COUNT(DISTINCT payments.user_id) AS count
      FROM payments
      INNER JOIN plans ON plans.id = payments.plan_id
      LEFT JOIN payment_methods ON payment_methods.user_id = payments.user_id
      WHERE #{active_target_where_sql}
        AND payment_methods.id IS NULL
    SQL
  end

  def action_list_sql
    <<~SQL.squish
      WITH target_payments AS (
        SELECT payments.*
        FROM payments
        INNER JOIN plans ON plans.id = payments.plan_id
        WHERE #{active_target_where_sql}
      )
      SELECT
        CASE
          WHEN payment_methods.id IS NULL THEN 'E_no_local_payment_method'
          WHEN payment_methods.spreedly_redacted_at IS NOT NULL THEN 'D_redacted_recard_required'
          WHEN payment_methods.archived_at IS NOT NULL AND payment_methods.vault_token IS NOT NULL AND payment_methods.vault_token <> '' THEN 'B_archived_token_requires_permission'
          WHEN payment_methods.vault_token IS NULL OR payment_methods.vault_token = '' THEN 'C_missing_token_search_backups'
          ELSE 'A_retry_candidate_token_exists'
        END AS bucket,
        target_payments.user_id AS user_id,
        COALESCE(users.first_name || ' ' || users.last_name, users.email, '') AS client_name,
        users.email AS email,
        STRING_AGG(DISTINCT target_payments.plan_id::text, ',') AS plan_ids,
        COUNT(target_payments.id) AS payment_count,
        SUM(target_payments.payment_amount) AS total_amount,
        payment_methods.id AS payment_method_id,
        payment_methods.card_brand AS card_brand,
        payment_methods.last4 AS last4,
        CASE WHEN payment_methods.vault_token IS NOT NULL AND payment_methods.vault_token <> '' THEN 'yes' ELSE 'no' END AS token_present,
        CASE WHEN payment_methods.archived_at IS NOT NULL THEN 'yes' ELSE 'no' END AS archived,
        CASE WHEN payment_methods.spreedly_redacted_at IS NOT NULL THEN 'yes' ELSE 'no' END AS redacted,
        MAX(target_payments.decline_reason) AS last_decline_reason
      FROM target_payments
      LEFT JOIN users ON users.id = target_payments.user_id
      LEFT JOIN payment_methods ON payment_methods.id = target_payments.payment_method_id
      GROUP BY
        bucket,
        target_payments.user_id,
        users.first_name,
        users.last_name,
        users.email,
        payment_methods.id,
        payment_methods.card_brand,
        payment_methods.last4,
        payment_methods.vault_token,
        payment_methods.archived_at,
        payment_methods.spreedly_redacted_at
      ORDER BY bucket, total_amount DESC NULLS LAST
      LIMIT #{MAX_REVIEW_ROWS}
    SQL
  end
end
