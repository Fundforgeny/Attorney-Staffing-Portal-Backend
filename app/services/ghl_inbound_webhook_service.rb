class GhlInboundWebhookService
  include HTTParty

  def initialize(webhook_url)
    @webhook_url = webhook_url
  end

  def post(payload)
    self.class.post(
      @webhook_url,
      headers: { "Content-Type" => "application/json" },
      body: payload.to_json
    )
  end
end
