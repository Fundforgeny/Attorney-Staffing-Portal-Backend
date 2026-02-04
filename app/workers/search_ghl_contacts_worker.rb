# app/workers/search_ghl_contacts_worker.rb
class SearchGhlContactsWorker
  include Sidekiq::Worker

  def perform(user_id)
    @user = User.find(user_id)
    log_info "Searching GHL for User ##{user_id} (#{@user.email})"
    Firm.find_each do |firm|
      process_firm_sync(firm)
    end

    log_info "GHL account search completed for User ##{user_id}"
  rescue StandardError => e
    Rails.logger.error "GHL Contact Search failed: #{e.message}"
    raise e
  end

  private

	def process_firm_sync(firm)
    attributes = {}
    
    firm_contact_id = nil
    
    if firm.ghl_api_key.present?
      firm_contact_id = fetch_ghl_contact_id(firm.ghl_api_key, firm.location_id)
      attributes[:contact_id] = firm_contact_id if firm_contact_id
    end

    existing_record = FirmUser.find_by(user: @user, firm: firm)
    
    if firm_contact_id || existing_record
      ff_id = fetch_ghl_contact_id(ENV["FUND_FORGE_API_KEY"], ENV["FUND_FORGE_LOCATION_ID"])
      attributes[:ghl_fund_forge_id] = ff_id if ff_id

      firm_user = existing_record || FirmUser.new(user: @user, firm: firm)
      firm_user.update!(attributes)
      log_info "Updated FirmUser (Firm: #{firm.name})"
    else
      log_info "Skipping #{firm.name}: User not found in GHL and no existing association."
    end
  end

  def fetch_ghl_contact_id(api_key, location_id)
    return nil if api_key.blank? || location_id.blank?

    service = GhlService.new(api_key, location_id)
    result = service.search_contacts(@user.email)

    return nil unless result[:success]
    
    result.dig(:body, "contacts")&.first&.fetch("id", nil)
  end

  def log_info(msg)
    puts "[GHL Search] #{msg}"
  end
end
