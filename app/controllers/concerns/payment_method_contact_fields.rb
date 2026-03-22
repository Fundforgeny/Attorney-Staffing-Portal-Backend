module PaymentMethodContactFields
  extend ActiveSupport::Concern

  private

  def extract_payment_method_contact_attrs(raw_params, user: nil)
    params = normalize_payment_method_contact_params(raw_params)
    payment_method_params = params[:payment_method].is_a?(Hash) ? params[:payment_method] : {}

    {
      cardholder_name: params[:cardholder_name].presence || payment_method_params[:cardholder_name].presence || user&.full_name,
      billing_email: params[:billing_email].presence || payment_method_params[:billing_email].presence || user&.email,
      billing_phone: params[:billing_phone].presence || payment_method_params[:billing_phone].presence || user&.phone,
      billing_address1: params[:billing_address1].presence || payment_method_params[:billing_address1].presence || user&.address_street,
      billing_address2: params[:billing_address2].presence || payment_method_params[:billing_address2].presence,
      billing_city: params[:billing_city].presence || payment_method_params[:billing_city].presence || user&.city,
      billing_state: params[:billing_state].presence || payment_method_params[:billing_state].presence || user&.state,
      billing_zip: params[:billing_zip].presence || payment_method_params[:billing_zip].presence || user&.zip_code,
      billing_country: params[:billing_country].presence || payment_method_params[:billing_country].presence || user&.country
    }.compact
  end

  def normalize_payment_method_contact_params(raw_params)
    return {} if raw_params.blank?

    hash = raw_params.respond_to?(:to_h) ? raw_params.to_h : raw_params
    hash.deep_symbolize_keys
  rescue StandardError
    {}
  end
end
