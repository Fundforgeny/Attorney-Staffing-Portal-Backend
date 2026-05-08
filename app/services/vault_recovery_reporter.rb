# frozen_string_literal: true

# Read-only reporter for understanding which saved cards may be recoverable.
#
# Operational model:
#   Client -> Payment Plan -> Payments
#
# Payment rows are implementation details. Recovery reporting should primarily
# show affected clients and affected plans. Payment counts are included only as
# "payments behind" under a plan, not as the headline metric.
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

  INACTIVE_PLAN_STATUSES = [
    Plan.statuses[:paid],
    Plan.statuses[:failed],
    Plan.statuses[:expired]
  ].freeze

  def print_report
    puts "\n=== Fund Forge Vault Recovery Report ==="
    puts "Generated at: #{Time.current}"
    puts "Environment: #{Rails.env}"
    puts ""

    print_payment_method_summary
    print_all_missing_token_records
    print_client_plan_recovery_summary
    print_client_plan_recoverability_buckets
    print_client_plan_action_list
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

    puts "--- Payment Method / Vault Summary ---"
    puts "Total saved card records:              #{PaymentMethod.count}"
    puts "Active local card records:             #{active_scope.count}"
    puts "Archived local card records:           #{archived_scope.count}"
    puts "Card records with vault_token:         #{token_present_scope.count}"
    puts "Card records missing vault_token:      #{token_missing_scope.count}"
    puts "Card records marked redacted locally:  #{redacted_scope.count}"
    puts "Archived + token present:              #{archived_scope.where.not(vault_token: [nil, ""]).count}"
    puts "Archived + token missing:              #{archived_scope.where(vault_token: [nil, ""]).count}"
    puts ""
  end

  def print_all_missing_token_records
    puts "--- All Missing Local Vault Token Card Records ---"
    rows = ActiveRecord::Base.connection.exec_query(all_missing_token_records_sql).to_a

    if rows.empty?
      puts "No saved card records are missing local vault_token."
      puts ""
      return
    end

    rows.each do |row|
      puts [
        "pm_id=#{row['payment_method_id']}",
        "user_id=#{row['user_id']}",
        "client=#{row['client_name']}",
        "email=#{row['email']}",
        "card=#{row['card_brand']} ****#{row['last4']}",
        "archived=#{row['archived']}",
        "redacted=#{row['redacted']}",
        "active_unpaid_plans=#{row['active_unpaid_plan_count']}",
        "inactive_plans=#{row['inactive_plan_count']}",
        "active_unpaid_plan_ids=#{row['active_unpaid_plan_ids'].presence || 'none'}",
        "all_plan_ids=#{row['all_plan_ids'].presence || 'none'}"
      ].join(" | ")
    end
    puts ""
  end

  def print_client_plan_recovery_summary
    puts "--- Client / Plan Recovery Summary ---"
    puts "Active unpaid clients needing card recovery: #{active_unpaid_client_count}"
    puts "Active unpaid plans needing card recovery:   #{active_unpaid_plan_count}"
    puts "Active unpaid plan exposure:                 #{money(active_unpaid_plan_exposure)}"
    puts "Active unpaid plans with missing token:       #{bucket_count(active_plans_missing_token_sql)}"
    puts "Active unpaid plans with redacted card:       #{bucket_count(active_plans_redacted_sql)}"
    puts "Active unpaid plans with usable local token:  #{bucket_count(active_plans_token_present_sql)}"
    puts ""
  end

  def print_client_plan_recoverability_buckets
    puts "--- Active Unpaid Recoverability Buckets: Clients / Plans ---"
    puts "A) Token exists locally, not redacted:         clients=#{bucket_count(active_clients_token_present_sql)} plans=#{bucket_count(active_plans_token_present_sql)}"
    puts "B) Archived token exists, needs permission:   clients=#{bucket_count(active_clients_archived_token_sql)} plans=#{bucket_count(active_plans_archived_token_sql)}"
    puts "C) Missing local token, ask Spreedly/backups: clients=#{bucket_count(active_clients_missing_token_sql)} plans=#{bucket_count(active_plans_missing_token_sql)}"
    puts "D) Redacted/not usable, likely re-card:       clients=#{bucket_count(active_clients_redacted_sql)} plans=#{bucket_count(active_plans_redacted_sql)}"
    puts "E) No local card record:                      clients=#{bucket_count(active_clients_no_card_sql)} plans=#{bucket_count(active_plans_no_card_sql)}"
    puts ""
  end

  def print_client_plan_action_list
    puts "--- Active Unpaid Action List: Client -> Plan -> Card ---"
    rows = ActiveRecord::Base.connection.exec_query(client_plan_action_list_sql).to_a

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
        "plan_id=#{row['plan_id']}",
        "plan_status=#{plan_status_name(row['plan_status'])}",
        "plan_name=#{row['plan_name']}",
        "remaining_balance=#{row['remaining_balance']}",
        "amount_behind=#{row['amount_behind']}",
        "payments_behind=#{row['payments_behind']}",
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
    puts "Headline metrics are clients and payment plans, not payment rows."
    puts "payments_behind is a sub-detail inside each plan and should not be used as the main recovery count."
    puts "Missing-token card records may affect multiple plans and many payment rows."
    puts "Archived cards with tokens are preserved but must not be charged unless expressly reactivated/permitted."
    puts "Cards missing local vault_token may be recoverable only from Spreedly, backups, or logs."
    puts "Cards actually redacted in Spreedly are generally not recoverable and require the client to re-enter card details."
    puts ""
  end

  def active_unpaid_client_count
    ActiveRecord::Base.connection.exec_query(active_unpaid_client_count_sql).first.fetch("count").to_i
  end

  def active_unpaid_plan_count
    ActiveRecord::Base.connection.exec_query(active_unpaid_plan_count_sql).first.fetch("count").to_i
  end

  def active_unpaid_plan_exposure
    ActiveRecord::Base.connection.exec_query(active_unpaid_plan_exposure_sql).first.fetch("amount").to_d
  end

  def money(value)
    "$#{format('%.2f', value.to_d)}"
  end

  def plan_status_name(value)
    Plan.statuses.invert[value.to_i] || value
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

  def inactive_plan_status_list
    INACTIVE_PLAN_STATUSES.join(",")
  end

  def active_target_where_sql
    <<~SQL.squish
      payments.needs_new_card = TRUE
      AND payments.payment_type = #{Payment.payment_types[:monthly_payment]}
      AND plans.status IN (#{active_plan_status_list})
    SQL
  end

  def active_plan_targets_cte
    <<~SQL.squish
      WITH plan_targets AS (
        SELECT
          plans.id AS plan_id,
          plans.user_id,
          plans.name AS plan_name,
          plans.status AS plan_status,
          plans.total_payment,
          plans.total_interest_amount,
          plans.monthly_payment,
          plans.next_payment_at,
          payments.payment_method_id,
          COUNT(payments.id) AS payments_behind,
          SUM(payments.payment_amount) AS amount_behind,
          MAX(payments.decline_reason) AS last_decline_reason
        FROM plans
        INNER JOIN payments ON payments.plan_id = plans.id
        WHERE #{active_target_where_sql}
        GROUP BY
          plans.id,
          plans.user_id,
          plans.name,
          plans.status,
          plans.total_payment,
          plans.total_interest_amount,
          plans.monthly_payment,
          plans.next_payment_at,
          payments.payment_method_id
      )
    SQL
  end

  def active_unpaid_client_count_sql
    <<~SQL.squish
      SELECT COUNT(DISTINCT plans.user_id) AS count
      FROM plans
      INNER JOIN payments ON payments.plan_id = plans.id
      WHERE #{active_target_where_sql}
    SQL
  end

  def active_unpaid_plan_count_sql
    <<~SQL.squish
      SELECT COUNT(DISTINCT plans.id) AS count
      FROM plans
      INNER JOIN payments ON payments.plan_id = plans.id
      WHERE #{active_target_where_sql}
    SQL
  end

  def active_unpaid_plan_exposure_sql
    <<~SQL.squish
      SELECT COALESCE(SUM(plan_exposure.amount), 0) AS amount
      FROM (
        SELECT DISTINCT plans.id, COALESCE(plans.total_payment, 0) + COALESCE(plans.total_interest_amount, 0) AS amount
        FROM plans
        INNER JOIN payments ON payments.plan_id = plans.id
        WHERE #{active_target_where_sql}
      ) plan_exposure
    SQL
  end

  def all_missing_token_records_sql
    <<~SQL.squish
      SELECT
        payment_methods.id AS payment_method_id,
        payment_methods.user_id AS user_id,
        COALESCE(users.first_name || ' ' || users.last_name, users.email, '') AS client_name,
        users.email AS email,
        payment_methods.card_brand AS card_brand,
        payment_methods.last4 AS last4,
        CASE WHEN payment_methods.archived_at IS NOT NULL THEN 'yes' ELSE 'no' END AS archived,
        CASE WHEN payment_methods.spreedly_redacted_at IS NOT NULL THEN 'yes' ELSE 'no' END AS redacted,
        COUNT(DISTINCT CASE WHEN plans.status IN (#{active_plan_status_list}) THEN plans.id END) AS active_unpaid_plan_count,
        COUNT(DISTINCT CASE WHEN plans.status IN (#{inactive_plan_status_list}) THEN plans.id END) AS inactive_plan_count,
        STRING_AGG(DISTINCT CASE WHEN plans.status IN (#{active_plan_status_list}) THEN plans.id::text END, ',') AS active_unpaid_plan_ids,
        STRING_AGG(DISTINCT plans.id::text, ',') AS all_plan_ids
      FROM payment_methods
      LEFT JOIN users ON users.id = payment_methods.user_id
      LEFT JOIN payments ON payments.payment_method_id = payment_methods.id
      LEFT JOIN plans ON plans.id = payments.plan_id
      WHERE payment_methods.vault_token IS NULL OR payment_methods.vault_token = ''
      GROUP BY
        payment_methods.id,
        payment_methods.user_id,
        users.first_name,
        users.last_name,
        users.email,
        payment_methods.card_brand,
        payment_methods.last4,
        payment_methods.archived_at,
        payment_methods.spreedly_redacted_at
      ORDER BY active_unpaid_plan_count DESC, payment_methods.id ASC
      LIMIT #{MAX_REVIEW_ROWS}
    SQL
  end

  def bucket_sql(condition, distinct_column)
    <<~SQL.squish
      #{active_plan_targets_cte}
      SELECT COUNT(DISTINCT #{distinct_column}) AS count
      FROM plan_targets
      LEFT JOIN payment_methods ON payment_methods.id = plan_targets.payment_method_id
      WHERE #{condition}
    SQL
  end

  def active_clients_token_present_sql
    bucket_sql("payment_methods.archived_at IS NULL AND payment_methods.spreedly_redacted_at IS NULL AND payment_methods.vault_token IS NOT NULL AND payment_methods.vault_token <> ''", "plan_targets.user_id")
  end

  def active_plans_token_present_sql
    bucket_sql("payment_methods.archived_at IS NULL AND payment_methods.spreedly_redacted_at IS NULL AND payment_methods.vault_token IS NOT NULL AND payment_methods.vault_token <> ''", "plan_targets.plan_id")
  end

  def active_clients_archived_token_sql
    bucket_sql("payment_methods.archived_at IS NOT NULL AND payment_methods.spreedly_redacted_at IS NULL AND payment_methods.vault_token IS NOT NULL AND payment_methods.vault_token <> ''", "plan_targets.user_id")
  end

  def active_plans_archived_token_sql
    bucket_sql("payment_methods.archived_at IS NOT NULL AND payment_methods.spreedly_redacted_at IS NULL AND payment_methods.vault_token IS NOT NULL AND payment_methods.vault_token <> ''", "plan_targets.plan_id")
  end

  def active_clients_missing_token_sql
    bucket_sql("payment_methods.id IS NOT NULL AND payment_methods.spreedly_redacted_at IS NULL AND (payment_methods.vault_token IS NULL OR payment_methods.vault_token = '')", "plan_targets.user_id")
  end

  def active_plans_missing_token_sql
    bucket_sql("payment_methods.id IS NOT NULL AND payment_methods.spreedly_redacted_at IS NULL AND (payment_methods.vault_token IS NULL OR payment_methods.vault_token = '')", "plan_targets.plan_id")
  end

  def active_clients_redacted_sql
    bucket_sql("payment_methods.spreedly_redacted_at IS NOT NULL", "plan_targets.user_id")
  end

  def active_plans_redacted_sql
    bucket_sql("payment_methods.spreedly_redacted_at IS NOT NULL", "plan_targets.plan_id")
  end

  def active_clients_no_card_sql
    bucket_sql("payment_methods.id IS NULL", "plan_targets.user_id")
  end

  def active_plans_no_card_sql
    bucket_sql("payment_methods.id IS NULL", "plan_targets.plan_id")
  end

  def client_plan_action_list_sql
    <<~SQL.squish
      #{active_plan_targets_cte}
      SELECT
        CASE
          WHEN payment_methods.id IS NULL THEN 'E_no_local_payment_method'
          WHEN payment_methods.spreedly_redacted_at IS NOT NULL THEN 'D_redacted_recard_required'
          WHEN payment_methods.archived_at IS NOT NULL AND payment_methods.vault_token IS NOT NULL AND payment_methods.vault_token <> '' THEN 'B_archived_token_requires_permission'
          WHEN payment_methods.vault_token IS NULL OR payment_methods.vault_token = '' THEN 'C_missing_token_search_backups'
          ELSE 'A_retry_candidate_token_exists'
        END AS bucket,
        plan_targets.user_id,
        COALESCE(users.first_name || ' ' || users.last_name, users.email, '') AS client_name,
        users.email,
        plan_targets.plan_id,
        plan_targets.plan_status,
        plan_targets.plan_name,
        (COALESCE(plan_targets.total_payment, 0) + COALESCE(plan_targets.total_interest_amount, 0)) AS remaining_balance,
        plan_targets.amount_behind,
        plan_targets.payments_behind,
        payment_methods.id AS payment_method_id,
        payment_methods.card_brand,
        payment_methods.last4,
        CASE WHEN payment_methods.vault_token IS NOT NULL AND payment_methods.vault_token <> '' THEN 'yes' ELSE 'no' END AS token_present,
        CASE WHEN payment_methods.archived_at IS NOT NULL THEN 'yes' ELSE 'no' END AS archived,
        CASE WHEN payment_methods.spreedly_redacted_at IS NOT NULL THEN 'yes' ELSE 'no' END AS redacted,
        plan_targets.last_decline_reason
      FROM plan_targets
      LEFT JOIN users ON users.id = plan_targets.user_id
      LEFT JOIN payment_methods ON payment_methods.id = plan_targets.payment_method_id
      ORDER BY bucket, amount_behind DESC NULLS LAST, plan_targets.plan_id ASC
      LIMIT #{MAX_REVIEW_ROWS}
    SQL
  end
end
