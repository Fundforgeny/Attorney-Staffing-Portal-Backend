module Webhooks
  # Receives Spreedly Account Updater batch callbacks.
  #
  # Configure this URL in the Spreedly dashboard under:
  #   Account Updater → Notification URL
  #   POST /webhooks/spreedly/account_updater
  #
  # Spreedly posts a JSON body for each updated payment method with the shape:
  #   {
  #     "payment_method": {
  #       "token": "abc123...",
  #       "storage_state": "retained",   # or "redacted" / "closed"
  #       "updated_at": "2026-03-30T...",
  #       "credit_card": {
  #         "month": 12,
  #         "year": 2029,
  #         "last_four_digits": "4242",
  #         "card_type": "visa"
  #       }
  #     }
  #   }
  #
  # Spreedly may also send a "transaction" wrapper for some event types.
  # We handle both shapes.
  #
  class SpreedlyAccountUpdaterController < ActionController::API
    before_action :verify_spreedly_signature

    def create
      SpreedlyAccountUpdaterWorker.perform_async(raw_payload)
      head :ok
    rescue StandardError => e
      Rails.logger.error("[AccountUpdater Webhook] Error: #{e.class}: #{e.message}")
      head :ok  # Always return 200 to Spreedly so they don't retry indefinitely
    end

    private

    def raw_payload
      request.raw_post
    end

    # Verify the X-Spreedly-Signature header using HMAC-SHA256.
    # Spreedly signs the raw request body with your signing secret.
    # Set SPREEDLY_WEBHOOK_SIGNING_SECRET in your environment variables.
    def verify_spreedly_signature
      secret = ENV["SPREEDLY_WEBHOOK_SIGNING_SECRET"].to_s
      return if secret.blank?  # Skip verification if secret not configured (dev/test)

      signature_header = request.headers["X-Spreedly-Signature"].to_s
      if signature_header.blank?
        Rails.logger.warn("[AccountUpdater Webhook] Missing X-Spreedly-Signature header")
        head :unauthorized and return
      end

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, raw_payload)
      unless ActiveSupport::SecurityUtils.secure_compare(expected, signature_header)
        Rails.logger.warn("[AccountUpdater Webhook] Invalid signature — possible spoofed request")
        head :unauthorized and return
      end
    end
  end
end
