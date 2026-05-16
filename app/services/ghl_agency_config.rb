class GhlAgencyConfig
  AGENCY_API_KEY_ENV = "GHL_AGENCY_API_KEY".freeze
  TITANS_LAW_LOCATION_ID_ENV = "TITANS_LAW_GHL_LOCATION_ID".freeze

  MissingConfigError = Class.new(StandardError)

  def self.api_key
    ENV[AGENCY_API_KEY_ENV].presence || GoogleSecretManagerSecret.fetch(AGENCY_API_KEY_ENV)
  end

  def self.titans_law_location_id
    ENV[TITANS_LAW_LOCATION_ID_ENV].presence
  end

  def self.configured?(location_id: nil)
    api_key.present? && location_id.present?
  end

  def self.require_config!(location_id: nil)
    missing = []
    missing << AGENCY_API_KEY_ENV if api_key.blank?
    missing << "firm.location_id or explicit location_id" if location_id.blank?

    return true if missing.empty?

    raise MissingConfigError, "Missing required agency GHL configuration: #{missing.join(', ')}"
  end

  def self.location_id_for_firm(firm)
    firm&.location_id.presence
  end

  def self.ghl_service(location_id:)
    require_config!(location_id: location_id)
    GhlService.new(api_key, location_id)
  end

  def self.ghl_service_for_firm(firm)
    ghl_service(location_id: location_id_for_firm(firm))
  end
end
