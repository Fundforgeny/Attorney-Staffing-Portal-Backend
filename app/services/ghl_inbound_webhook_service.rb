class GhlInboundWebhookService
  STATIC_WEBHOOK_URL = "https://services.leadconnectorhq.com/hooks/ypwiHcCIbSqZMzXzrIhd/webhook-trigger/2SKCzqieUupUzm8earmZ".freeze

  def initialize(webhook_url = STATIC_WEBHOOK_URL)
    @webhook_url = webhook_url
  end

  def self.resolve_webhook_url
    STATIC_WEBHOOK_URL
  end

  def call(payload, context: {})
    uri = URI.parse(@webhook_url)

    clean_payload = payload.compact

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(clean_payload)

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: 15,
      read_timeout: 30
    ) do |http|
      http.request(request)
    end

    Rails.logger.info("[GHL] Response: #{response.code} #{response.body}")
    response
  end
end
