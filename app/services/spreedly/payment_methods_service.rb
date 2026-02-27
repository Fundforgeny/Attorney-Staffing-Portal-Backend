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

    def update_payment_method(token:, full_name: nil, email: nil, zip: nil, metadata: nil)
      payload = {
        payment_method: {}
      }
      payload[:payment_method][:full_name] = full_name if full_name.present?
      payload[:payment_method][:email] = email if email.present?
      payload[:payment_method][:zip] = zip if zip.present?
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


