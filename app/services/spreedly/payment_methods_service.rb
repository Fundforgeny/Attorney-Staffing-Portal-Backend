module Spreedly
  class PaymentMethodsService
    def initialize(client: Spreedly::Client.new)
      @client = client
    end

    def create_credit_card(number:, month:, year:, verification_value:, full_name:, retained: true, metadata: {})
      response = @client.post(
        "/payment_methods.json",
        body: {
          payment_method: {
            retained: retained,
            credit_card: {
              number: number,
              month: month,
              year: year,
              verification_value: verification_value,
              full_name: full_name,
              metadata: metadata
            }
          }
        }
      )
      response.fetch("payment_method")
    end

    def update_payment_method(token:, cardholder_name: nil, billing_email: nil, billing_phone: nil, billing_address1: nil, billing_address2: nil, billing_city: nil, billing_state: nil, billing_zip: nil, billing_country: nil, metadata: nil)
      payload = {
        payment_method: {}
      }
      payload[:payment_method][:full_name] = cardholder_name if cardholder_name.present?
      payload[:payment_method][:email] = billing_email if billing_email.present?
      payload[:payment_method][:phone_number] = billing_phone if billing_phone.present?
      payload[:payment_method][:address1] = billing_address1 if billing_address1.present?
      payload[:payment_method][:address2] = billing_address2 if billing_address2.present?
      payload[:payment_method][:city] = billing_city if billing_city.present?
      payload[:payment_method][:state] = billing_state if billing_state.present?
      payload[:payment_method][:zip] = billing_zip if billing_zip.present?
      payload[:payment_method][:country] = billing_country if billing_country.present?
      payload[:payment_method][:metadata] = metadata if metadata.present?

      response = @client.put("/payment_methods/#{token}.json", body: payload)
      response.fetch("payment_method")
    end

    def redact_payment_method(token:)
      response = @client.put("/payment_methods/#{token}/redact.json")
      response.fetch("transaction")
    end
  end
end


