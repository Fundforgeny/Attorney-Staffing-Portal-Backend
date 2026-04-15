# app/services/ghl_billing_sync_service.rb
#
# Fetches billing address, email, and phone from a GHL contact record and
# persists any missing fields to the local User record.
#
# Used by RecurringChargeService before each charge attempt to ensure we
# always pass complete billing data to Stripe/Spreedly (required for Radar).
#
# PRIORITY ORDER (law firm first):
#   1. Law firm GHL sub-account (Titans Law, Ironclad, etc.) via firm.ghl_api_key
#      and firm_users.contact_id — this is where billing address lives.
#   2. Fund Forge GHL sub-account via firm_users.ghl_fund_forge_id — fallback
#      only when no law firm record exists.
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

  # Force-syncs all fields from GHL regardless of whether they are already set.
  # Useful for bulk backfill runs.
  def force_sync!
    contact_data = fetch_ghl_contact
    return false unless contact_data

    update_user_from_contact!(contact_data, force: true)
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

  # Always try the law firm GHL first — that is where billing address is stored.
  # Fall back to Fund Forge GHL only if no law firm record exists.
  def fetch_ghl_contact
    # 1. Law firm GHL sub-account (Titans Law, Ironclad, etc.)
    #    Uses firm.ghl_api_key + firm.location_id + firm_users.contact_id
    law_firm_user = FirmUser.joins(:firm)
                            .where(user: user)
                            .where.not(firms: { name: FUND_FORGE_FIRM_NAME })
                            .where.not(contact_id: [nil, ""])
                            .order(updated_at: :desc)
                            .first

    if law_firm_user&.contact_id.present?
      firm = law_firm_user.firm
      if firm.ghl_api_key.present? && firm.location_id.present?
        result = GhlService.new(firm.ghl_api_key, firm.location_id)
                           .get_contact(law_firm_user.contact_id)
        if result[:success] && result[:body].is_a?(Hash)
          contact = result[:body]["contact"]
          Rails.logger.info("[GhlBillingSync] Fetched contact from law firm GHL: firm=#{firm.name} user_id=#{user.id}")
          return contact if contact
        else
          Rails.logger.warn("[GhlBillingSync] Law firm GHL fetch failed: firm=#{firm.name} user_id=#{user.id} status=#{result[:status]}")
        end
      end
    end

    # 2. Fund Forge GHL sub-account (fallback)
    #    Uses ENV keys + firm_users.ghl_fund_forge_id
    ff_firm_user = FirmUser.joins(:firm)
                           .where(user: user, firms: { name: FUND_FORGE_FIRM_NAME })
                           .first

    if ff_firm_user&.ghl_fund_forge_id.present?
      ff_firm = ff_firm_user.firm
      api_key     = ff_firm.ghl_api_key.presence || ENV["FUND_FORGE_API_KEY"]
      location_id = ff_firm.location_id.presence || ENV["FUND_FORGE_LOCATION_ID"]

      if api_key.present? && location_id.present?
        result = GhlService.new(api_key, location_id)
                           .get_contact(ff_firm_user.ghl_fund_forge_id)
        if result[:success] && result[:body].is_a?(Hash)
          contact = result[:body]["contact"]
          Rails.logger.info("[GhlBillingSync] Fetched contact from Fund Forge GHL (fallback): user_id=#{user.id}")
          return contact if contact
        else
          Rails.logger.warn("[GhlBillingSync] Fund Forge GHL fetch failed: user_id=#{user.id} status=#{result[:status]}")
        end
      end
    end

    Rails.logger.warn("[GhlBillingSync] No GHL contact found for user_id=#{user.id} email=#{user.email}")
    nil
  end

  def update_user_from_contact!(contact, force: false)
    updates = {}

    # When force=true, overwrite existing values; otherwise only fill blanks.
    should_update = ->(current_val) { force ? true : current_val.blank? }

    updates[:email]          = contact["email"]      if should_update.call(user.email)      && contact["email"].present?
    updates[:phone]          = contact["phone"]      if should_update.call(user.phone)      && contact["phone"].present?
    updates[:address_street] = contact["address1"]   if should_update.call(user.address_street) && contact["address1"].present?
    updates[:city]           = contact["city"]       if should_update.call(user.city)       && contact["city"].present?
    updates[:state]          = contact["state"]      if should_update.call(user.state)      && contact["state"].present?
    updates[:postal_code]    = contact["postalCode"] if should_update.call(user.postal_code) && contact["postalCode"].present?
    updates[:country]        = contact["country"]    if should_update.call(user.country)    && contact["country"].present?
    updates[:first_name]     = contact["firstName"]  if should_update.call(user.first_name) && contact["firstName"].present?
    updates[:last_name]      = contact["lastName"]   if should_update.call(user.last_name)  && contact["lastName"].present?

    return false if updates.empty?

    user.update_columns(updates)
    Rails.logger.info("[GhlBillingSync] Updated user_id=#{user.id} fields=#{updates.keys.join(', ')}")
    true
  rescue => e
    Rails.logger.warn("[GhlBillingSync] Failed to update user_id=#{user.id}: #{e.message}")
    false
  end
end
