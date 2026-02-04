# app/services/square_payment_service.rb
class SquarePaymentService
  def initialize(payments)
    @down_payment = payments.find { |p| p.payment_amount > 0 }
    return unless @down_payment

    response = make_charge_request
    handle_response(response)
  end

  private

  attr_reader :down_payment

  def make_charge_request
    relay_url = ENV['EVERVAULT_SANDBOX_SQUARE_RELAY_URL']

    HTTParty.post(
      relay_url,
      body: payload.to_json,
      headers: {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{ENV['SQUARE_ACCESS_TOKEN']}",
        "Square-Version" => "2025-10-16",
        "x-evervault-api-key" => ENV['EVERVAULT_API_KEY'],
        "x-evervault-app-id" => ENV['EVERVAULT_APP_ID']
      }
    )
  end

  def payload
    vault_token = down_payment.payment_method.vault_token
    {
      idempotency_key: SecureRandom.uuid,
      amount_money: {
        amount: down_payment.total_payment_including_fee.to_i,
        currency: "USD"
      },
      source_id: "cnon:card-nonce-ok", # Replace this with the actual sqaure card nonce for the prod account
      autocomplete: true,
      note: down_payment&.payment_type,
      billing_address: {
        given_name: down_payment.user.first_name,
        family_name: down_payment.user.last_name
      }
    }
  end

  def handle_response(response)
    Rails.logger.info "Square via Evervault response: #{response.parsed_response.inspect}"

    if response.code == 200 && response.parsed_response["payment"]&.dig("status") == "COMPLETED"
      payment = response.parsed_response["payment"]

      down_payment.update!(
        status: :succeeded,
        charge_id: payment["id"],
        paid_at: Time.current
      )
    else
      error_message = response.parsed_response.dig("errors", 0, "detail") ||
                      response.parsed_response.dig("error", "message") ||
                      "Unknown Square error"

      down_payment.update!(status: :failed)

      raise "Square payment failed (via Evervault): #{error_message}"
    end
  end
end
