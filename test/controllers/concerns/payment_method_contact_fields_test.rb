require_relative '../../test_helper'

class PaymentMethodContactFieldsTest < Minitest::Test
  class DummyController
    include PaymentMethodContactFields

    public :extract_payment_method_contact_attrs
  end

  UserStub = Struct.new(:full_name, :email, :phone, :address_street, :city, :state, :zip_code, :country)

  def setup
    @subject = DummyController.new
  end

  def test_extracts_top_level_and_nested_fields_with_user_fallbacks
    user = UserStub.new('Jane Doe', 'jane@example.com', '5551234567', '123 Main', 'Austin', 'TX', '78701', 'US')

    attrs = @subject.extract_payment_method_contact_attrs({
      billing_phone: '5550001111',
      payment_method: {
        billing_city: 'Dallas'
      }
    }, user: user)

    assert_equal 'Jane Doe', attrs[:cardholder_name]
    assert_equal 'jane@example.com', attrs[:billing_email]
    assert_equal '5550001111', attrs[:billing_phone]
    assert_equal '123 Main', attrs[:billing_address1]
    assert_equal 'Dallas', attrs[:billing_city]
    assert_equal 'TX', attrs[:billing_state]
    assert_equal '78701', attrs[:billing_zip]
    assert_equal 'US', attrs[:billing_country]
  end
end
