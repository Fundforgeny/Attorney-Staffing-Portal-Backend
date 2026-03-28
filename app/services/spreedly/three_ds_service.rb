module Spreedly
  class ThreeDsService
    def initialize(client: Spreedly::Client.new)
      @client = client
    end

    def initiate_purchase(payment_method_token:, amount_cents:, currency: "USD", callback_url:, redirect_url:, workflow_key: nil, gateway_token: nil, browser_info: nil, sca_provider_key: nil, ip: nil)
      payload = {
        transaction: {
          payment_method_token: payment_method_token,
          amount: amount_cents,
          currency_code: currency,
          retain_on_success: true,
          callback_url: callback_url,
          redirect_url: redirect_url,
          callback_format: "json"
        }
      }
      payload[:transaction][:ip] = ip if ip.present?
      # Use workflow_key for Composer routing, or gateway_token for direct gateway (bypasses Composer)
      if workflow_key.present?
        payload[:transaction][:workflow_key] = workflow_key
      elsif gateway_token.present?
        payload[:transaction][:gateway_token] = gateway_token
      end

      # 3DS2 Global: use sca_provider_key (mutually exclusive with attempt_3dsecure)
      if sca_provider_key.present?
        payload[:transaction][:sca_provider_key] = sca_provider_key
        payload[:transaction][:browser_info] = browser_info if browser_info.present?
        if (test_params = test_sca_authentication_parameters).present?
          payload[:transaction][:sca_authentication_parameters] = test_params
        end
      else
        payload[:transaction][:attempt_3dsecure] = true
      end

      response = @client.post(
        "/transactions/purchase.json",
        body: payload
      )
      response.fetch("transaction")
    end

    def fetch_transaction(transaction_token:)
      response = @client.get("/transactions/#{transaction_token}.json")
      response.fetch("transaction")
    end


    # Never use top-level transaction["redirect_url"] — that is the merchant return URL we sent
    # (Spreedly echoes it). Using it as "challenge_url" breaks Lifecycle / iframe flows.
    def extract_challenge_url(transaction)
      transaction["checkout_url"].presence ||
        transaction.dig("three_ds_context", "redirect_url").presence ||
        transaction.dig("sca_authentication", "challenge_form_embed_url").presence ||
        acs_action_from_sca_challenge_form(transaction)
    end

    # Spreedly often returns challenge as HTML (device_fingerprint / challenge) with no embed URL.
    def acs_action_from_sca_challenge_form(transaction)
      html = transaction.dig("sca_authentication", "challenge_form")
      return nil if html.blank?

      html.to_s.match(/\baction\s*=\s*["']([^"']+)["']/i)&.[](1)
    end

    # Fields for browser 3DS2 Global (Lifecycle, iframe, or form POST).
    def challenge_client_fields(transaction)
      sca = sca_authentication(transaction)
      optional = {
        sca_required_action: sca["required_action"],
        challenge_form_html: sca["challenge_form"],
        challenge_form_embed_url: sca["challenge_form_embed_url"],
        sca_authentication_token: sca["token"],
        managed_order_token: sca["managed_order_token"],
        authentication_value: sca["authentication_value"],
        eci: sca["eci"],
        xid: sca["xid"],
        directory_server_transaction_id: sca["directory_server_transaction_id"],
        three_ds_server_trans_id: sca["three_ds_server_trans_id"],
        three_ds_version: sca["three_ds_version"],
        flow_performed: sca["flow_performed"],
        trans_status_reason: sca["trans_status_reason"],
        enrolled: sca["enrolled"],
        authenticated: sca["authenticated"]
      }.compact

      {
        challenge_url: extract_challenge_url(transaction),
        fingerprint_required: fingerprint_required?(transaction),
        fingerprint_status: fingerprint_status(transaction),
        fingerprint_completed: fingerprint_completed?(transaction),
        three_ds_lifecycle_required: pending_sca_browser_step?(transaction),
        transaction_state: transaction["state"],
        authentication_status_text: authentication_status_text(transaction)
      }.merge(optional)
    end

    def pending_sca_browser_step?(transaction)
      return false unless transaction.is_a?(Hash)
      return false unless transaction["state"].to_s == "pending"

      sca = sca_authentication(transaction)
      sca["challenge_form"].present? || sca["required_action"].present?
    end

    def fingerprint_required?(transaction)
      sca_authentication(transaction)["required_action"].to_s == "device_fingerprint"
    end

    def fingerprint_completed?(transaction)
      pending_sca_browser_step?(transaction) && !fingerprint_required?(transaction)
    end

    def fingerprint_status(transaction)
      return "required" if fingerprint_required?(transaction)
      return "completed" if fingerprint_completed?(transaction)
      return "not_applicable" unless pending_sca_browser_step?(transaction)

      "not_required"
    end

    def authentication_status_text(transaction)
      sca = sca_authentication(transaction)
      parts = []
      parts << "state=#{transaction["state"]}" if transaction["state"].present?
      parts << "required_action=#{sca["required_action"]}" if sca["required_action"].present?
      parts << "authenticated=#{sca["authenticated"]}" unless sca["authenticated"].nil?
      parts << "enrolled=#{sca["enrolled"]}" if sca["enrolled"].present?
      parts << "eci=#{sca["eci"]}" if sca["eci"].present?

      parts.join(" ").presence
    end

    def terminal_state?(state)
      %w[succeeded failed gateway_processing_failed scrubbed].include?(state.to_s)
    end

    # Test SCA provider requires test_scenario or Spreedly returns failed SCA with a message about
    # "valid scenario" — see https://developer.spreedly.com/docs/testing-your-3ds2-global-integration
    def test_sca_authentication_parameters
      scenario = ENV["SPREEDLY_3DS_TEST_SCENARIO"].to_s.strip.presence
      return {} if scenario.blank?

      test_scenario = { scenario: scenario }
      if ActiveModel::Type::Boolean.new.cast(ENV.fetch("SPREEDLY_3DS_TEST_SCENARIO_SKIP_BROWSER", "false"))
        test_scenario[:skip_browser] = true
      end
      { test_scenario: test_scenario }
    end

    private

    def sca_authentication(transaction)
      sca = transaction["sca_authentication"]
      sca.is_a?(Hash) ? sca : {}
    end
  end
end
