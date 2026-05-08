# frozen_string_literal: true

# Read-only validator for local Spreedly vault tokens.
#
# It checks whether token-bearing payment methods are still present/retained in
# Spreedly, without charging, redacting, archiving, or changing payment state.
#
class VaultTokenValidator
  MAX_ROWS = 100

  def initialize(scope: :active_targets)
    @scope = scope.to_sym
    @service = Spreedly::PaymentMethodsService.new
  end

  def print_report
    puts "\n=== Spreedly Vault Token Validation Report ==="
    puts "Generated at: #{Time.current}"
    puts "Scope: #{@scope}"
    puts ""

    rows = payment_methods_to_check.limit(MAX_ROWS)
    if rows.empty?
      puts "No local vault tokens found for this scope."
      return
    end

    rows.each do |payment_method|
      print_validation_row(payment_method)
    end
  rescue StandardError => e
    Rails.logger.error("[VaultTokenValidator] Failed: #{e.class}: #{e.message}")
    puts "[VaultTokenValidator] Failed: #{e.class}: #{e.message}"
  end

  private

  attr_reader :service

  def payment_methods_to_check
    base = PaymentMethod.where.not(vault_token: [nil, ""])

    case @scope
    when :all
      base.order(:id)
    when :redacted_local
      base.where.not(spreedly_redacted_at: nil).order(:id)
    else
      base
        .joins(user: { payments: :plan })
        .where(payments: { needs_new_card: true, payment_type: Payment.payment_types[:monthly_payment] })
        .where(plans: { status: active_plan_statuses })
        .distinct
        .order(:id)
    end
  end

  def active_plan_statuses
    [
      Plan.statuses[:draft],
      Plan.statuses[:agreement_generated],
      Plan.statuses[:payment_pending]
    ]
  end

  def print_validation_row(payment_method)
    spreedly_pm = service.get_payment_method(token: payment_method.vault_token)
    storage_state = spreedly_pm["storage_state"].presence || "unknown"

    puts [
      "pm_id=#{payment_method.id}",
      "user_id=#{payment_method.user_id}",
      "card=#{payment_method.card_brand} ****#{payment_method.last4}",
      "local_redacted=#{payment_method.spreedly_redacted_at.present? ? 'yes' : 'no'}",
      "archived=#{payment_method.archived_at.present? ? 'yes' : 'no'}",
      "spreedly_state=#{storage_state}",
      "usable=#{usable_state?(storage_state) ? 'maybe' : 'no'}"
    ].join(" | ")
  rescue Spreedly::Error => e
    puts [
      "pm_id=#{payment_method.id}",
      "user_id=#{payment_method.user_id}",
      "card=#{payment_method.card_brand} ****#{payment_method.last4}",
      "local_redacted=#{payment_method.spreedly_redacted_at.present? ? 'yes' : 'no'}",
      "archived=#{payment_method.archived_at.present? ? 'yes' : 'no'}",
      "spreedly_state=lookup_error",
      "usable=unknown",
      "error=#{sanitize_error(e.message)}"
    ].join(" | ")
  end

  def usable_state?(storage_state)
    %w[retained cached].include?(storage_state.to_s)
  end

  def sanitize_error(message)
    message.to_s.gsub(/01[A-Z0-9]{20,}/, "[token-redacted]").truncate(160)
  end
end
