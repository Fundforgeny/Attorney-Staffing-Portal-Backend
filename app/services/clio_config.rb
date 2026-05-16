class ClioConfig
  ACCESS_TOKEN_ENV = "CLIO_ACCESS_TOKEN".freeze
  BASE_URL_ENV = "CLIO_API_BASE_URL".freeze
  DEFAULT_BASE_URL = "https://app.clio.com/api/v4".freeze

  MissingConfigError = Class.new(StandardError)

  def self.access_token
    ENV[ACCESS_TOKEN_ENV].presence
  end

  def self.base_url
    ENV[BASE_URL_ENV].presence || DEFAULT_BASE_URL
  end

  def self.configured?
    access_token.present?
  end

  def self.require_config!
    return true if configured?

    raise MissingConfigError, "Missing required Clio OAuth access token: #{ACCESS_TOKEN_ENV}"
  end
end
