module Spreedly
  class PaymentMethodsService
    UPDATABLE_FIELDS = %i[
      full_name
      first_name
      last_name
      email
      phone_number
      company
      address1
      address2
      city
      state
      zip
      country
      shipping_address1
      shipping_address2
      shipping_city
      shipping_state
      shipping_zip
      shipping_country
      shipping_phone_number
      metadata
    ].freeze

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

    def update_payment_method(token:, **attributes)
      payment_method = attributes.slice(*UPDATABLE_FIELDS).compact_blank
      return get_payment_method(token: token) if payment_method.blank?

      response = @client.put("/payment_methods/#{token}.json", body: { payment_method: payment_method })
      response.fetch("payment_method")
    end

    def get_payment_method(token:)
      response = @client.get("/payment_methods/#{token}.json")
      response.fetch("payment_method")
    end

    def redact_payment_method(token:)
      response = @client.put("/payment_methods/#{token}/redact.json")
      response.fetch("transaction")
    end
  end
end
