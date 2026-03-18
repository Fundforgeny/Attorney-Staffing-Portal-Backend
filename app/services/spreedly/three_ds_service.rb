module Spreedly
  class ThreeDsService
    def initialize(client: Spreedly::Client.new)
      @client = client
    end

    def initiate_purchase(payment_method_token:, amount_cents:, currency: "USD", callback_url:, redirect_url:, workflow_key: nil)
      payload = {
        transaction: {
          payment_method_token: payment_method_token,
          amount: amount_cents,
          currency_code: currency,
          retain_on_success: true,
          attempt_3dsecure: true,
          callback_url: callback_url,
          redirect_url: redirect_url
        }
      }
      payload[:transaction][:workflow_key] = workflow_key if workflow_key.present?

      response = @client.post(
        "/transactions/authorize.json",
        body: payload
      )
      response.fetch("transaction")
    end

    def fetch_transaction(transaction_token:)
      response = @client.get("/transactions/#{transaction_token}.json")
      response.fetch("transaction")
    end

    def extract_challenge_url(transaction)
      transaction["checkout_url"].presence ||
        transaction["redirect_url"].presence ||
        transaction.dig("three_ds_context", "redirect_url").presence
    end

    def terminal_state?(state)
      %w[succeeded failed gateway_processing_failed scrubbed].include?(state.to_s)
    end
  end
end


