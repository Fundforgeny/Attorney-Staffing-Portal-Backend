# frozen_string_literal: true

# Controlled one-record token restore helper.
#
# This service is intentionally narrow. It only restores a known/recovered token
# onto one specific PaymentMethod after validating that Spreedly recognizes the
# token. It does not charge the card. It does not auto-clear needs_new_card.
#
class VaultTokenRestorer
  def initialize(payment_method_id:, vault_token:, reactivate: false)
    @payment_method_id = payment_method_id
    @vault_token = vault_token.to_s.strip
    @reactivate = ActiveModel::Type::Boolean.new.cast(reactivate)
    @service = Spreedly::PaymentMethodsService.new
  end

  def call
    raise ArgumentError, "payment_method_id is required" if payment_method_id.blank?
    raise ArgumentError, "vault_token is required" if vault_token.blank?

    payment_method = PaymentMethod.find(payment_method_id)
    spreedly_pm = service.get_payment_method(token: vault_token)
    storage_state = spreedly_pm["storage_state"].to_s

    unless %w[retained cached].include?(storage_state)
      raise "Spreedly token is not usable. storage_state=#{storage_state.presence || 'unknown'}"
    end

    updates = {
      vault_token: vault_token,
      spreedly_redacted_at: nil,
      last_updated_via_spreedly_at: Time.current,
      updated_at: Time.current
    }

    if reactivate
      updates[:archived_at] = nil
      updates[:is_default] = true
    end

    PaymentMethod.transaction do
      if reactivate
        payment_method.user.payment_methods.active.update_all(is_default: false)
      end

      payment_method.update_columns(updates)
    end

    puts [
      "RESTORED",
      "pm_id=#{payment_method.id}",
      "user_id=#{payment_method.user_id}",
      "card=#{payment_method.card_brand} ****#{payment_method.last4}",
      "spreedly_state=#{storage_state}",
      "reactivated=#{reactivate ? 'yes' : 'no'}"
    ].join(" | ")

    payment_method
  end

  private

  attr_reader :payment_method_id, :vault_token, :reactivate, :service
end
