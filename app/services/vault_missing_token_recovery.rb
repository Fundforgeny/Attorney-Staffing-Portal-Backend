# frozen_string_literal: true

# VaultMissingTokenRecovery
#
# Attempts to recover missing local vault_token values by looking up historical
# Spreedly transaction tokens stored on payments. This does NOT recover full card
# numbers. It only restores a token if Spreedly exposes the original payment method
# token on a historical transaction and the metadata matches the local row.
#
# Safety:
#   - does not charge cards
#   - does not redact cards
#   - does not use archived cards
#   - does not clear needs_new_card automatically
#   - validates recovered token with Spreedly before writing
#   - only applies when local last4 matches Spreedly last4 when both exist
#
class VaultMissingTokenRecovery
  MAX_PAYMENT_METHODS = 100
  MAX_TRANSACTIONS_PER_PM = 25

  ACTIVE_PLAN_STATUSES = [
    Plan.statuses[:draft],
    Plan.statuses[:agreement_generated],
    Plan.statuses[:payment_pending]
  ].freeze

  def initialize(apply: true)
    @apply = ActiveModel::Type::Boolean.new.cast(apply)
    @client = Spreedly::Client.new
    @payment_method_service = Spreedly::PaymentMethodsService.new
    @stats = Hash.new(0)
  end

  def call
    puts "\n=== Missing Vault Token Recovery ==="
    puts "Generated at: #{Time.current}"
    puts "Mode: #{apply ? 'APPLY_SAFE_RESTORES' : 'DRY_RUN'}"
    puts ""

    target_payment_methods.find_each(batch_size: 25) do |payment_method|
      stats[:payment_methods_checked] += 1
      attempt_recovery(payment_method)
    end

    puts ""
    puts "--- Missing Token Recovery Summary ---"
    puts "Payment methods checked:      #{stats[:payment_methods_checked]}"
    puts "Transactions checked:         #{stats[:transactions_checked]}"
    puts "Candidate tokens found:       #{stats[:candidate_tokens_found]}"
    puts "Tokens restored:              #{stats[:tokens_restored]}"
    puts "Skipped no candidate:         #{stats[:no_candidate]}"
    puts "Skipped mismatch/unusable:    #{stats[:mismatch_or_unusable]}"
    puts "Errors:                       #{stats[:errors]}"
    puts ""
  rescue StandardError => e
    Rails.logger.error("[VaultMissingTokenRecovery] Failed: #{e.class}: #{e.message}")
    puts "[VaultMissingTokenRecovery] Failed: #{e.class}: #{e.message}"
  end

  private

  attr_reader :apply, :client, :payment_method_service, :stats

  def target_payment_methods
    PaymentMethod
      .where(vault_token: [nil, ""])
      .where(spreedly_redacted_at: nil)
      .joins("INNER JOIN payments ON payments.payment_method_id = payment_methods.id")
      .joins("INNER JOIN plans ON plans.id = payments.plan_id")
      .where(payments: { needs_new_card: true, payment_type: Payment.payment_types[:monthly_payment] })
      .where(plans: { status: ACTIVE_PLAN_STATUSES })
      .distinct
      .order(:id)
      .limit(MAX_PAYMENT_METHODS)
  end

  def attempt_recovery(payment_method)
    candidate = candidate_token_for(payment_method)

    unless candidate
      stats[:no_candidate] += 1
      puts recovery_line(payment_method, "no_candidate", nil)
      return
    end

    stats[:candidate_tokens_found] += 1

    unless candidate_matches_payment_method?(candidate, payment_method)
      stats[:mismatch_or_unusable] += 1
      puts recovery_line(payment_method, "candidate_mismatch", candidate)
      return
    end

    unless token_usable?(candidate[:token])
      stats[:mismatch_or_unusable] += 1
      puts recovery_line(payment_method, "candidate_not_usable", candidate)
      return
    end

    if apply
      payment_method.update_columns(
        vault_token: candidate[:token],
        last_updated_via_spreedly_at: Time.current,
        updated_at: Time.current
      )
      stats[:tokens_restored] += 1
      puts recovery_line(payment_method, "restored", candidate)
    else
      puts recovery_line(payment_method, "would_restore", candidate)
    end
  rescue StandardError => e
    stats[:errors] += 1
    puts recovery_line(payment_method, "error=#{sanitize(e.message)}", nil)
  end

  def candidate_token_for(payment_method)
    historical_transactions(payment_method).each do |transaction_token|
      stats[:transactions_checked] += 1
      transaction = fetch_transaction(transaction_token)
      candidate = extract_payment_method_candidate(transaction, transaction_token)
      return candidate if candidate&.dig(:token).present?
    end

    nil
  end

  def historical_transactions(payment_method)
    Payment
      .where(payment_method_id: payment_method.id)
      .where.not(charge_id: [nil, ""])
      .order(updated_at: :desc)
      .limit(MAX_TRANSACTIONS_PER_PM)
      .pluck(:charge_id)
      .uniq
  end

  def fetch_transaction(transaction_token)
    client.get("/transactions/#{transaction_token}.json").fetch("transaction")
  rescue Spreedly::Error => e
    Rails.logger.warn("[VaultMissingTokenRecovery] Transaction lookup failed token=#{sanitize(transaction_token)}: #{sanitize(e.message)}")
    nil
  end

  def extract_payment_method_candidate(transaction, transaction_token)
    return nil if transaction.blank?

    pm = transaction["payment_method"] || transaction.dig("payment_method", "payment_method")
    return nil unless pm.is_a?(Hash)

    token = pm["token"].presence || pm["payment_method_token"].presence
    return nil if token.blank?

    {
      token: token,
      transaction_token: transaction_token,
      last4: pm["last_four_digits"].presence || pm["last4"].presence,
      card_brand: pm["card_type"].presence || pm["card_brand"].presence,
      storage_state: pm["storage_state"].presence
    }
  end

  def candidate_matches_payment_method?(candidate, payment_method)
    candidate_last4 = candidate[:last4].to_s.strip
    local_last4 = payment_method.last4.to_s.strip

    return true if candidate_last4.blank? || local_last4.blank?

    candidate_last4 == local_last4
  end

  def token_usable?(vault_token)
    response = payment_method_service.get_payment_method(token: vault_token)
    pm = response.is_a?(Hash) ? response["payment_method"] : nil
    storage_state = pm&.dig("storage_state").to_s
    %w[retained cached].include?(storage_state)
  rescue Spreedly::Error => e
    Rails.logger.warn("[VaultMissingTokenRecovery] Candidate token validation failed: #{sanitize(e.message)}")
    false
  end

  def recovery_line(payment_method, result, candidate)
    [
      "pm_id=#{payment_method.id}",
      "user_id=#{payment_method.user_id}",
      "card=#{payment_method.card_brand} ****#{payment_method.last4}",
      "result=#{result}",
      candidate ? "source_transaction=#{sanitize(candidate[:transaction_token])}" : nil,
      candidate ? "candidate_card=#{candidate[:card_brand]} ****#{candidate[:last4]}" : nil
    ].compact.join(" | ")
  end

  def sanitize(value)
    value.to_s.gsub(/01[A-Z0-9]{20,}/, "[token-redacted]").truncate(160)
  end
end
