require "base64"
require "cgi"
require "json"
require "net/http"
require "uri"

class GoogleSecretManagerSecret
  PROJECT_ENV = "GOOGLE_CLOUD_PROJECT".freeze
  PROJECT_FALLBACK_ENV = "GCP_PROJECT".freeze
  SECRET_PROJECT_ENV_SUFFIX = "_SECRET_PROJECT".freeze
  METADATA_TOKEN_URL = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token".freeze
  SECRET_MANAGER_HOST = "secretmanager.googleapis.com".freeze

  class << self
    def fetch(secret_id, project: nil)
      resolved_project = project.presence || project_for(secret_id)
      return nil if resolved_project.blank?

      token = access_token
      return nil if token.blank?

      read_secret(secret_id, resolved_project, token)
    rescue StandardError => e
      Rails.logger.warn("[GoogleSecretManagerSecret] secret fetch unavailable secret_id=#{secret_id} error=#{e.class}: #{e.message}") if defined?(Rails)
      nil
    end

    def project_for(secret_id)
      ENV["#{secret_id}#{SECRET_PROJECT_ENV_SUFFIX}"].presence ||
        ENV[PROJECT_ENV].presence ||
        ENV[PROJECT_FALLBACK_ENV].presence
    end

    private

    def access_token
      ENV["GOOGLE_OAUTH_ACCESS_TOKEN"].presence || metadata_token
    end

    def metadata_token
      uri = URI.parse(METADATA_TOKEN_URL)
      request = Net::HTTP::Get.new(uri)
      request["Metadata-Flavor"] = "Google"

      response = Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 2) do |http|
        http.request(request)
      end

      return nil unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)["access_token"].presence
    rescue StandardError
      nil
    end

    def read_secret(secret_id, project, token)
      uri = URI.parse(
        "https://#{SECRET_MANAGER_HOST}/v1/projects/#{CGI.escape(project)}/secrets/#{CGI.escape(secret_id)}/versions/latest:access"
      )
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.request(request)
      end

      return nil unless response.is_a?(Net::HTTPSuccess)

      encoded = JSON.parse(response.body).dig("payload", "data")
      return nil if encoded.blank?

      Base64.decode64(encoded).presence
    end
  end
end
