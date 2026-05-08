# frozen_string_literal: true

# VaultRecoveryAutopilot
#
# One-command recovery workflow for vaulted card issues.
#
# What it does:
#   1. Prints the active/unpaid recovery report.
#   2. Validates local token-bearing payment methods against Spreedly.
#   3. Safely fixes local false-redacted records when Spreedly says the token is
#      still retained/cached.
#   4. Prints a final report.
#
# What it does NOT do:
#   - It does not charge cards.
#   - It does not redact cards.
#   - It does not restore missing vault tokens unless a recovered token is
#     explicitly supplied through vault:restore_token.
#   - It does not use archived cards or reactivate cards without permission.
#   - It does not clear needs_new_card automatically; payment retry policy should
#     decide that after card validity/permission is confirmed.
#
class VaultRecoveryAutopilot
  MAX_FIX_ROWS = 200

  ACTIVE_PLAN_STATUSES = [
    Plan.statuses[:draft],
    Plan.statuses[:agreement_generated],
    Plan.statuses[:payment_pending]
  ].freeze

  def initialize(apply: true)
    @apply = ActiveModel::Type::Boolean.new.cast(apply)
    @service = Spreedly::PaymentMethodsService.new
    @stats = Hash.new(0)
  end

  def call
    puts "\n=== Vault Recovery Autopilot ==="
    puts "Generated at: #{Time.current}"
    puts "Environment: #{Rails.env}"
    puts "Mode: #{apply ? 'APPLY_SAFE_FIXES' : 'DRY_RUN'}"
    puts ""

    puts "--- Before Report ---"
    VaultRecoveryReporter.new.print_report

    puts "--- Token Validation + Safe Local Fixes ---"
    process_payment_methods

    puts "--- Autopilot Summary ---"
    puts "Checked token-bearing payment methods:      #{stats[:checked]}"
    puts "Spreedly retained/cached:                   #{stats[:retained]}"
    puts "Spreedly redacted/missing/error:            #{stats[:not_usable]}"
    puts "Local false-redacted candidates:            #{stats[:false_redacted_candidates]}"
    puts "Local false-redacted fixed:                 #{stats[:false_redacted_fixed]}"
    puts "Missing local token records found:          #{missing_token_target_count}"
    puts "Redacted-in-Spreedly likely recard needed:  #{stats[:redacted_remote]}"
    puts ""

    puts "--- After Report ---"
    VaultRecoveryReporter.new.print_report
  rescue StandardError => e
    Rails.logger.error("[VaultRecoveryAutopilot] Failed: #{e.class}: #{e.message}")
    puts "[VaultRecoveryAutopilot] Failed: #{e.class}: #{e.message}"
  end

  private

  attr_reader :apply, :service, :stats

  def process_payment_methods
    target_payment_methods.find_each(batch_size: 50) do |payment_method|
      stats[:checked] += 1
      validate_and_fix(payment_method)
    end
  end

  def target_payment_methods
    # Do not rely on User has_many :payments; that association is not currently
    # defined. Join explicitly from payment_methods.user_id to payments.user_id.
    PaymentMethod
      .where.not(vault_token: [nil, ""])
      .joins("INNER JOIN payments ON payments.user_id = payment_methods.user_id")
      .joins("INNER JOIN plans ON plans.id = payments.plan_id")
      .where(payments: { needs_new_card: true, payment_type: Payment.payment_types[:monthly_payment] })
      .where(plans: { status: ACTIVE_PLAN_STATUSES })
      .distinct
      .order("payment_methods.id ASC")
      .limit(MAX_FIX_ROWS)
  end

  def validate_and_fix(payment_method)
    spreedly_pm = service.get_payment_method(token: payment_method.vault_token)
    storage_state = spreedly_pm["storage_state"].to_s

    if usable_storage_state?(storage_state)
      stats[:retained] += 1
      fix_false_redacted!(payment_method, storage_state)
    else
      stats[:not_usable] += 1
      stats[:redacted_remote] += 1 if storage_state == "redacted"
      puts validation_line(payment_method, storage_state, "remote_not_usable")
    end
  rescue Spreedly::Error => e
    stats[:not_usable] += 1
    puts validation_line(payment_method, "lookup_error", sanitize_error(e.message))
  rescue StandardError => e
    stats[:not_usable] += 1
    puts validation_line(payment_method, "unexpected_error", sanitize_error("#{e.class}: #{e.message}"))
  end

  def fix_false_redacted!(payment_method, storage_state)
    if payment_method.spreedly_redacted_at.present?
      stats[:false_redacted_candidates] += 1

      if apply
        payment_method.update_columns(
          spreedly_redacted_at: nil,
          last_updated_via_spreedly_at: Time.current,
          updated_at: Time.current
        )
        stats[:false_redacted_fixed] += 1
        puts validation_line(payment_method, storage_state, "fixed_local_false_redacted")
      else
        puts validation_line(payment_method, storage_state, "would_fix_local_false_redacted")
      end
    else
      puts validation_line(payment_method, storage_state, "ok")
    end
  end

  def usable_storage_state?(storage_state)
    %w[retained cached].include?(storage_state)
  end

  def missing_token_target_count
    Payment
      .joins(:plan, :payment_method)
      .where(needs_new_card: true, payment_type: Payment.payment_types[:monthly_payment])
      .where(plans: { status: ACTIVE_PLAN_STATUSES })
      .where(payment_methods: { vault_token: [nil, ""] })
      .distinct
      .count("payment_methods.id")
  end

  def validation_line(payment_method, storage_state, result)
    [
      "pm_id=#{payment_method.id}",
      "user_id=#{payment_method.user_id}",
      "card=#{payment_method.card_brand} ****#{payment_method.last4}",
      "local_redacted=#{payment_method.spreedly_redacted_at.present? ? 'yes' : 'no'}",
      "archived=#{payment_method.archived_at.present? ? 'yes' : 'no'}",
      "spreedly_state=#{storage_state.presence || 'unknown'}",
      "result=#{result}"
    ].join(" | ")
  end

  def sanitize_error(message)
    message.to_s.gsub(/01[A-Z0-9]{20,}/, "[token-redacted]").truncate(160)
  end
end
