module Spreedly
  class ThreeDsService
    def initialize(client: Spreedly::Client.new)
      @client = client
    end

    def initiate_purchase(payment_method_token:, amount_cents:, currency: "USD", callback_url:, redirect_url:, workflow_key: nil, browser_info: nil, sca_provider_key: nil, ip: nil)
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
      payload[:transaction][:workflow_key] = workflow_key if workflow_key.present?

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
      sca = transaction["sca_authentication"]
      sca = sca.is_a?(Hash) ? sca : {}
      optional = {
        sca_required_action: sca["required_action"],
        challenge_form_html: sca["challenge_form"],
        sca_authentication_token: sca["token"]
      }.compact

      { challenge_url: extract_challenge_url(transaction) }.merge(optional)
    end

    def pending_sca_browser_step?(transaction)
      return false unless transaction.is_a?(Hash)
      return false unless transaction["state"].to_s == "pending"

      sca = transaction["sca_authentication"]
      return false unless sca.is_a?(Hash)

      sca["challenge_form"].present? || sca["required_action"].present?
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
  end
end


