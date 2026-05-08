# frozen_string_literal: true

# Read-only reporter for understanding which saved cards may be recoverable.
#
# This service intentionally does not modify any records and does not print full
# vault tokens or raw Spreedly transaction payloads. It is safe to run from Render
# logs or manually via rake task.
#
class VaultRecoveryReporter
  MAX_REVIEW_ROWS = 100

  def print_report
    puts "\n=== Fund Forge Vault Recovery Report ==="
    puts "Generated at: #{Time.current}"
    puts "Environment: #{Rails.env}"
    puts ""

    print_payment_method_summary
    print_payment_recovery_summary
    print_recoverability_buckets
    print_review_rows
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
    puts "Payments needing new card:             #{Payment.where(needs_new_card: true).count}"
    puts "Monthly payments needing new card:     #{monthly_payment_scope.where(needs_new_card: true).count}"
    puts "Failed monthly payments:               #{monthly_payment_scope.where(status: Payment.statuses[:failed]).count}"
    puts "Pending monthly payments:              #{monthly_payment_scope.where(status: Payment.statuses[:pending]).count}"
    puts ""
  end

  def print_recoverability_buckets
    puts "--- Recoverability Buckets: Distinct Clients With needs_new_card Payments ---"
    puts "A) Active card with token:              #{bucket_count(active_with_token_sql)}"
    puts "B) Archived card with token:            #{bucket_count(archived_with_token_sql)}"
    puts "C) Local card exists but token missing: #{bucket_count(local_card_no_token_sql)}"
    puts "D) Local card marked redacted:          #{bucket_count(local_redacted_sql)}"
    puts "E) No local payment method:             #{bucket_count(no_local_payment_method_sql)}"
    puts ""
  end

  def print_review_rows
    puts "--- Top #{MAX_REVIEW_ROWS} Payments Needing Card / Recovery Review ---"
    rows = ActiveRecord::Base.connection.exec_query(review_rows_sql).to_a

    if rows.empty?
      puts "No payments currently marked needs_new_card=true."
      puts ""
      return
    end

    rows.each do |row|
      puts [
        "payment_id=#{row['payment_id']}",
        "user_id=#{row['user_id']}",
        "client=#{row['client_name']}",
        "email=#{row['email']}",
        "payment_status=#{payment_status_name(row['payment_status'])}",
        "plan_status=#{plan_status_name(row['plan_status'])}",
        "amount=#{row['amount']}",
        "pm_id=#{row['payment_method_id'] || 'none'}",
        "card=#{row['card_brand']} ****#{row['last4']}",
        "token_present=#{row['token_present']}",
        "archived=#{row['archived']}",
        "redacted=#{row['redacted']}",
        "decline=#{sanitize_decline_reason(row['decline_reason'])}"
      ].join(" | ")
    end
    puts ""
  end

  def print_notes
    puts "--- Notes ---"
    puts "Recoverable without client re-entry usually means a vault_token is still present locally."
    puts "Archived cards with tokens are intentionally preserved but must not be charged unless expressly reactivated/permitted."
    puts "Cards missing local vault_token may still be recoverable only if the token exists in a DB backup, logs, or Spreedly transaction history."
    puts "Cards actually redacted in Spreedly are generally not recoverable and require the client to re-enter card details."
    puts ""
  end

  def monthly_payment_scope
    Payment.respond_to?(:monthly_payment) ? Payment.monthly_payment : Payment.where(payment_type: Payment.payment_types[:monthly_payment])
  end

  def payment_status_name(value)
    Payment.statuses.invert[value.to_i] || value
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

  def active_with_token_sql
    <<~SQL.squish
      SELECT COUNT(DISTINCT payments.user_id) AS count
      FROM payments
      INNER JOIN payment_methods ON payment_methods.user_id = payments.user_id
      WHERE payments.needs_new_card = TRUE
        AND payment_methods.archived_at IS NULL
        AND payment_methods.vault_token IS NOT NULL
        AND payment_methods.vault_token <> ''
    SQL
  end

  def archived_with_token_sql
    <<~SQL.squish
      SELECT COUNT(DISTINCT payments.user_id) AS count
      FROM payments
      INNER JOIN payment_methods ON payment_methods.user_id = payments.user_id
      WHERE payments.needs_new_card = TRUE
        AND payment_methods.archived_at IS NOT NULL
        AND payment_methods.vault_token IS NOT NULL
        AND payment_methods.vault_token <> ''
    SQL
  end

  def local_card_no_token_sql
    <<~SQL.squish
      SELECT COUNT(DISTINCT payments.user_id) AS count
      FROM payments
      INNER JOIN payment_methods ON payment_methods.user_id = payments.user_id
      WHERE payments.needs_new_card = TRUE
        AND (payment_methods.vault_token IS NULL OR payment_methods.vault_token = '')
    SQL
  end

  def local_redacted_sql
    <<~SQL.squish
      SELECT COUNT(DISTINCT payments.user_id) AS count
      FROM payments
      INNER JOIN payment_methods ON payment_methods.user_id = payments.user_id
      WHERE payments.needs_new_card = TRUE
        AND payment_methods.spreedly_redacted_at IS NOT NULL
    SQL
  end

  def no_local_payment_method_sql
    <<~SQL.squish
      SELECT COUNT(DISTINCT payments.user_id) AS count
      FROM payments
      LEFT JOIN payment_methods ON payment_methods.user_id = payments.user_id
      WHERE payments.needs_new_card = TRUE
        AND payment_methods.id IS NULL
    SQL
  end

  def review_rows_sql
    <<~SQL.squish
      SELECT
        payments.id AS payment_id,
        payments.user_id AS user_id,
        COALESCE(users.first_name || ' ' || users.last_name, users.email, '') AS client_name,
        users.email AS email,
        payments.status AS payment_status,
        plans.status AS plan_status,
        payments.payment_amount AS amount,
        payments.decline_reason AS decline_reason,
        payment_methods.id AS payment_method_id,
        payment_methods.card_brand AS card_brand,
        payment_methods.last4 AS last4,
        CASE WHEN payment_methods.vault_token IS NOT NULL AND payment_methods.vault_token <> '' THEN 'yes' ELSE 'no' END AS token_present,
        CASE WHEN payment_methods.archived_at IS NOT NULL THEN 'yes' ELSE 'no' END AS archived,
        CASE WHEN payment_methods.spreedly_redacted_at IS NOT NULL THEN 'yes' ELSE 'no' END AS redacted
      FROM payments
      LEFT JOIN users ON users.id = payments.user_id
      LEFT JOIN plans ON plans.id = payments.plan_id
      LEFT JOIN payment_methods ON payment_methods.id = payments.payment_method_id
      WHERE payments.needs_new_card = TRUE
      ORDER BY payments.updated_at DESC
      LIMIT #{MAX_REVIEW_ROWS}
    SQL
  end
end
