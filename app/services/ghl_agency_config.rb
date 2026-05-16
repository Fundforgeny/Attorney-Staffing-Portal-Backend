class GhlAgencyConfig
  AGENCY_API_KEY_ENV = "GHL_AGENCY_API_KEY".freeze
  DEFAULT_LOCATION_ID_ENV = "GHL_DEFAULT_LOCATION_ID".freeze
  TITANS_LAW_LOCATION_ID_ENV = "TITANS_LAW_GHL_LOCATION_ID".freeze

  MissingConfigError = Class.new(StandardError)

  def self.api_key
    ENV[AGENCY_API_KEY_ENV].presence
  end

  def self.default_location_id
    ENV[DEFAULT_LOCATION_ID_ENV].presence
  end

  def self.titans_law_location_id
    ENV[TITANS_LAW_LOCATION_ID_ENV].presence || default_location_id
  end

  def self.configured?(location_id: nil)
    api_key.present? && (location_id.presence || default_location_id).present?
  end

  def self.require_config!(location_id: nil)
    missing = []
    missing << AGENCY_API_KEY_ENV if api_key.blank?
    missing << DEFAULT_LOCATION_ID_ENV if location_id.blank? && default_location_id.blank?

    return true if missing.empty?

    raise MissingConfigError, "Missing required agency GHL configuration: #{missing.join(', ')}"
  end

  def self.ghl_service(location_id: nil)
    resolved_location_id = location_id.presence || default_location_id
    require_config!(location_id: resolved_location_id)
    GhlService.new(api_key, resolved_location_id)
  end
end
