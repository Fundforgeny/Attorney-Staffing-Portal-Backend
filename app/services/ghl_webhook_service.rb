require "net/http"

class GhlWebhookService
  WEBHOOK_URL = "https://services.leadconnectorhq.com/hooks/ypwiHcCIbSqZMzXzrIhd/webhook-trigger/6TXApF9cSV2jsioESYoE".freeze

  def self.send_login_magic_link!(user:, login_magic_link:)
    payload = {
      email: user.email,
      first_name: user.first_name,
      phone: user.phone,
      login_magic_link: login_magic_link
    }

    uri = URI.parse(WEBHOOK_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri, { "Content-Type" => "application/json" })
    request.body = payload.to_json

    response = http.request(request)
    
    return if response.is_a?(Net::HTTPSuccess)

    raise StandardError, "GHL webhook failed with status #{response.code}: #{response.body}"
  rescue StandardError => e
    Rails.logger.error("GhlWebhookService error: #{e.message}")
    raise
  end

  def self.send_admin_login_magic_link!(admin:, login_magic_link:)
    payload = {
      email: admin.email,
      first_name: admin.first_name,
      last_name: admin.last_name,
      phone: admin.contact_number,
      login_magic_link: login_magic_link,
      portal_type: "admin"
    }

    uri = URI.parse(WEBHOOK_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri, { "Content-Type" => "application/json" })
    request.body = payload.to_json

    response = http.request(request)

    return if response.is_a?(Net::HTTPSuccess)

    raise StandardError, "GHL admin webhook failed with status #{response.code}: #{response.body}"
  rescue StandardError => e
    Rails.logger.error("GhlWebhookService admin error: #{e.message}")
    raise
  end
end
