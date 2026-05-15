class TalentHubGhlConfig
  API_KEY_ENV = "TITANS_LAW_TALENT_HUB_GHL_API_KEY".freeze
  LOCATION_ID_ENV = "TITANS_LAW_TALENT_HUB_LOCATION_ID".freeze

  MissingConfigError = Class.new(StandardError)

  def self.api_key
    ENV[API_KEY_ENV].presence
  end

  def self.location_id
    ENV[LOCATION_ID_ENV].presence
  end

  def self.configured?
    api_key.present? && location_id.present?
  end

  def self.require_config!
    missing = []
    missing << API_KEY_ENV if api_key.blank?
    missing << LOCATION_ID_ENV if location_id.blank?

    return true if missing.empty?

    raise MissingConfigError, "Missing required Talent Hub GHL configuration: #{missing.join(', ')}"
  end

  def self.ghl_service
    require_config!
    GhlService.new(api_key, location_id)
  end
end
