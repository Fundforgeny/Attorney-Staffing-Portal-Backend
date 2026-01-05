# app/services/stripe_payment_service.rb
class StripePaymentService
  def initialize(payments)
    @down_payment = payments.find { |p| p.payment_amount > 0 }
    return unless @down_payment

    response = make_charge_request

    handle_response(response)
  end

  def make_charge_request
    relay_url = ENV["EVERVAULT_STRIPE_RELAY_URL"]
    HTTParty.post(
      relay_url,
      body: payload,
      headers: {
				"Content-Type" => "application/x-www-form-urlencoded",
				"Authorization" => "Bearer #{ENV['STRIPE_SECRET_KEY']}",
				"x-evervault-api-key" => ENV["EVERVAULT_API_KEY"],
				"x-evervault-app-id" => ENV["EVERVAULT_APP_ID"]
			}
    )
  end

  def payload
    vault_token = @down_payment.payment_method.vault_token
    {
      amount: @down_payment.total_payment_including_fee.to_i,
      currency: "usd",
      payment_method_data: {
        type: "card",
        card: {
					number: vault_token["number"],
					exp_month: vault_token["exp_month"].to_i,
					exp_year: vault_token["exp_year"].to_i,
					cvc: vault_token["cvc"]
				},
        billing_details: {
          name: "#{@down_payment.user.first_name} #{@down_payment.user.last_name}"
        }
      },
      automatic_payment_methods: {
        enabled: true,
        allow_redirects: "never"
      },
      confirm: true,
      description: "Down payment"
    }
  end

  def handle_response(response)
    puts "Response: #{response.parsed_response}"

    if response.code == 200
      @down_payment.update!(
        status: :succeeded,
        charge_id: response.parsed_response["id"],
        paid_at: Time.current
      )
    else
      @down_payment.update!(status: :failed)
      raise "Payment processing through Evervault(Stripe) failed: #{response.parsed_response["error"]["message"]}"
    end
  end
end
