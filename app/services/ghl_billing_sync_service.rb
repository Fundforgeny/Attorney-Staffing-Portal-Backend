# app/services/ghl_billing_sync_service.rb
#
# Fetches billing address, email, and phone from a GHL contact record and
# persists any missing fields to the local User record.
#
# Used by RecurringChargeService before each charge attempt to ensure we
# always pass complete billing data to Stripe/Spreedly (required for Radar).
#
# Usage:
#   GhlBillingSyncService.new(user).sync_if_needed!
#
class GhlBillingSyncService
  FUND_FORGE_FIRM_NAME = "Fund Forge".freeze

  def initialize(user)
    @user = user
  end

  # Syncs billing data from GHL if any required fields are missing.
  # Returns true if any fields were updated, false otherwise.
  def sync_if_needed!
    return false if billing_complete?

    contact_data = fetch_ghl_contact
    return false unless contact_data

    update_user_from_contact!(contact_data)
  end

  # Returns true only if all Stripe Radar required fields are present.
  def billing_complete?
    @user.email.present? &&
      @user.address_street.present? &&
      @user.city.present? &&
      @user.state.present? &&
      @user.postal_code.present?
  end

  private

  attr_reader :user

  # Try Fund Forge GHL first (ghl_fund_forge_id), then the law firm GHL (contact_id).
  def fetch_ghl_contact
    # 1. Fund Forge sub-account
    ff_firm_user = FirmUser.joins(:firm)
                           .where(user: user, firms: { name: FUND_FORGE_FIRM_NAME })
                           .first
    if ff_firm_user&.ghl_fund_forge_id.present?
      result = ghl_service_for(ENV["FUND_FORGE_API_KEY"], ENV["FUND_FORGE_LOCATION_ID"])
                 &.get_contact(ff_firm_user.ghl_fund_forge_id)
      return result[:body]["contact"] if result&.dig(:success) && result[:body].is_a?(Hash)
    end

    # 2. Law firm GHL sub-account
    law_firm_user = FirmUser.joins(:firm)
                            .where(user: user)
                            .where.not(firms: { name: FUND_FORGE_FIRM_NAME })
                            .where.not(contact_id: [nil, ""])
                            .first
    if law_firm_user&.contact_id.present?
      firm = law_firm_user.firm
      result = ghl_service_for(firm.ghl_api_key, firm.ghl_location_id)
                 &.get_contact(law_firm_user.contact_id)
      return result[:body]["contact"] if result&.dig(:success) && result[:body].is_a?(Hash)
    end

    nil
  end

  def ghl_service_for(api_key, location_id)
    return nil if api_key.blank? || location_id.blank?
    GhlService.new(api_key, location_id)
  end

  def update_user_from_contact!(contact)
    updates = {}

    updates[:email]          = contact["email"]   if user.email.blank? && contact["email"].present?
    updates[:phone]          = contact["phone"]   if user.phone.blank? && contact["phone"].present?
    updates[:address_street] = contact["address1"] if user.address_street.blank? && contact["address1"].present?
    updates[:city]           = contact["city"]    if user.city.blank? && contact["city"].present?
    updates[:state]          = contact["state"]   if user.state.blank? && contact["state"].present?
    updates[:postal_code]    = contact["postalCode"] if user.postal_code.blank? && contact["postalCode"].present?
    updates[:country]        = contact["country"] if user.country.blank? && contact["country"].present?

    # Also try first/last name if missing
    updates[:first_name] = contact["firstName"] if user.first_name.blank? && contact["firstName"].present?
    updates[:last_name]  = contact["lastName"]  if user.last_name.blank? && contact["lastName"].present?

    return false if updates.empty?

    user.update_columns(updates)
    Rails.logger.info("[GhlBillingSync] Updated user_id=#{user.id} fields=#{updates.keys.join(', ')}")
    true
  rescue => e
    Rails.logger.warn("[GhlBillingSync] Failed to update user_id=#{user.id}: #{e.message}")
    false
  end
end
