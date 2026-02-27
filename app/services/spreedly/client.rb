module Spreedly
  class Error < StandardError
    attr_reader :status, :payload

    def initialize(message, status: nil, payload: nil)
      super(message)
      @status = status
      @payload = payload
    end
  end

  class Client
    include HTTParty
    base_uri "https://core.spreedly.com/v1"

    def initialize
      @environment_key = ENV["SPREEDLY_ENV_KEY"].presence || ENV["SPREEDLY_ENVIRONMENT_KEY"].presence
      @access_secret = ENV["SPREEDLY_ACCESS_SECRET"].presence
      raise Error, "Missing Spreedly credentials" if @environment_key.blank? || @access_secret.blank?
    end

    def get(path, query: nil)
      request(:get, path, query: query)
    end

    def post(path, body: nil)
      request(:post, path, body: body)
    end

    def put(path, body: nil)
      request(:put, path, body: body)
    end

    private

    def request(method, path, body: nil, query: nil)
      options = {
        basic_auth: { username: @environment_key, password: @access_secret },
        headers: { "Content-Type" => "application/json" }
      }
      options[:query] = query if query.present?
      options[:body] = body.to_json if body.present?

      response = self.class.public_send(method, path, options)
      parsed = JSON.parse(response.body) rescue {}
      ok = response.code.to_i.between?(200, 299)
      return parsed if ok

      message = parsed.dig("transaction", "message").presence ||
                parsed.dig("error", "message").presence ||
                parsed.dig("errors", 0, "message").presence ||
                "Spreedly request failed"
      raise Error.new(message, status: response.code.to_i, payload: parsed)
    end
  end
end


