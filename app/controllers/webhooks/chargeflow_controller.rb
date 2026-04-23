module Webhooks
  # Receives Chargeflow webhook events.
  #
  # Configure this URL in the Chargeflow dashboard:
  #   POST /webhooks/chargeflow
  #
  # Supported events:
  #   alerts.created   — A Chargeflow alert was created for a transaction.
  #                      Action: apply $100 fee to the plan, add "chargeback" tag in GHL.
  #
  #   dispute.created  — A dispute was opened on a transaction.
  #                      Action: mark payment as disputed, restore balance, stop future
  #                      auto-charges on the plan, add "chargeback" tag in GHL.
  #
  # Chargeflow automatically refunds the transaction; Fund Forge only needs to
  # update its own records and notify GHL.
  #
  # Webhook signature verification uses the CHARGEFLOW_WEBHOOK_SECRET env var.
  # The signature is sent in the X-Chargeflow-Signature header as an HMAC-SHA256
  # hex digest of the raw request body.
  #
  class ChargeflowController < ActionController::API
    before_action :verify_chargeflow_signature

    def receive
      event_type = params[:event] || params.dig(:data, :event)

      Rails.logger.info("[Chargeflow Webhook] event=#{event_type} payload_keys=#{params.keys.inspect}")

      case event_type.to_s
      when "alerts.created"
        ChargeflowAlertWorker.perform_async(raw_payload)
      when "dispute.created"
        ChargeflowDisputeWorker.perform_async(raw_payload)
      else
        Rails.logger.info("[Chargeflow Webhook] Unhandled event type: #{event_type} — ignoring")
      end

      head :ok
    rescue StandardError => e
      Rails.logger.error("[Chargeflow Webhook] Error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      head :ok  # Always return 200 so Chargeflow does not retry indefinitely
    end

    private

    def raw_payload
      request.raw_post
    end

    # Verify the X-Chargeflow-Signature header using HMAC-SHA256.
    # Set CHARGEFLOW_WEBHOOK_SECRET in your environment variables.
    # If the secret is not configured (dev/test), skip verification.
    def verify_chargeflow_signature
      secret = ENV["CHARGEFLOW_WEBHOOK_SECRET"].to_s
      return if secret.blank?

      signature_header = request.headers["X-Chargeflow-Signature"].to_s

      if signature_header.blank?
        Rails.logger.warn("[Chargeflow Webhook] Missing X-Chargeflow-Signature header")
        head :unauthorized and return
      end

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, raw_payload)
      unless ActiveSupport::SecurityUtils.secure_compare(expected, signature_header)
        Rails.logger.warn("[Chargeflow Webhook] Invalid signature — possible spoofed request")
        head :unauthorized and return
      end
    end
  end
end
