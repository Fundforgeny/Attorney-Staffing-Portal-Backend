require_relative '../test_helper'

class SpreedlyPaymentMethodsServiceTest < Minitest::Test
  class FakeClient
    attr_reader :path, :body

    def put(path, body:)
      @path = path
      @body = body
      {
        'payment_method' => body[:payment_method].transform_keys(&:to_s)
      }
    end
  end

  def test_update_payment_method_sends_extended_billing_fields
    client = FakeClient.new
    service = Spreedly::PaymentMethodsService.new(client: client)

    response = service.update_payment_method(
      token: 'vault_123',
      cardholder_name: 'Jane Doe',
      billing_email: 'jane@example.com',
      billing_phone: '5550001111',
      billing_address1: '123 Main',
      billing_address2: 'Apt 4',
      billing_city: 'Austin',
      billing_state: 'TX',
      billing_zip: '78701',
      billing_country: 'US',
      metadata: { source: 'checkout' }
    )

    assert_equal '/payment_methods/vault_123.json', client.path
    assert_equal 'Jane Doe', client.body[:payment_method][:full_name]
    assert_equal '5550001111', client.body[:payment_method][:phone_number]
    assert_equal '123 Main', client.body[:payment_method][:address1]
    assert_equal 'Apt 4', client.body[:payment_method][:address2]
    assert_equal 'Austin', client.body[:payment_method][:city]
    assert_equal 'TX', client.body[:payment_method][:state]
    assert_equal '78701', client.body[:payment_method][:zip]
    assert_equal 'US', client.body[:payment_method][:country]
    assert_equal({ 'phone_number' => '5550001111', 'address1' => '123 Main', 'country' => 'US', 'metadata' => { source: 'checkout' }, 'full_name' => 'Jane Doe', 'email' => 'jane@example.com', 'address2' => 'Apt 4', 'city' => 'Austin', 'state' => 'TX', 'zip' => '78701' }, response)
  end
end
