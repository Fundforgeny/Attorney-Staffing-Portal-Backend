class Api::V1::PaymentMethodsController < ActionController::API
  include ApiResponse
  include Devise::Controllers::Helpers

  before_action :authenticate_user!
  before_action :set_payment_method, only: [ :show, :update, :destroy, :set_default ]

  def index
    payment_methods = current_user.payment_methods.ordered_for_user
    render_success(data: payment_methods.map { |payment_method| serialize_payment_method(payment_method) }, status: :ok)
  end

  def show
    render_success(data: serialize_payment_method(@payment_method, spreedly_payment_method: spreedly_payment_method_snapshot(@payment_method)), status: :ok)
  end

  def create
    if create_params[:vault_token].blank?
      return render_error(message: "vault_token is required", status: :bad_request)
    end

    sync_attrs = spreedly_payment_method_attributes(create_params)
    spreedly_payment_method = Spreedly::PaymentMethodsService.new.update_payment_method(token: create_params[:vault_token], **sync_attrs)

    payment_method = current_user.payment_methods.find_or_initialize_by(vault_token: create_params[:vault_token])
    payment_method.assign_attributes(
      provider: create_params[:provider].presence || payment_method.provider.presence || "Spreedly Vault",
      last4: create_params[:last4].presence || payment_method.last4,
      card_brand: create_params[:card_brand].presence || payment_method.card_brand,
      exp_month: create_params[:exp_month].presence || payment_method.exp_month,
      exp_year: create_params[:exp_year].presence || payment_method.exp_year,
      cardholder_name: create_params[:cardholder_name].presence || payment_method.cardholder_name,
      last_updated_via_spreedly_at: Time.current
    )

    created = payment_method.new_record?

    ActiveRecord::Base.transaction do
      if ActiveModel::Type::Boolean.new.cast(create_params[:is_default]) || current_user.payment_methods.blank?
        current_user.payment_methods.update_all(is_default: false)
        payment_method.is_default = true
      end
      payment_method.save!
    end

    render_success(
      data: serialize_payment_method(payment_method, spreedly_payment_method: spreedly_payment_method),
      message: created ? "Payment method added successfully" : "Payment method refreshed successfully",
      status: created ? :created : :ok
    )
  rescue ActiveRecord::RecordInvalid => e
    render_error(errors: e.record.errors.full_messages, status: :unprocessable_entity)
  rescue Spreedly::Error => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def update
    spreedly = Spreedly::PaymentMethodsService.new
    spreadly_updated = spreedly.update_payment_method(
      token: @payment_method.vault_token,
      **spreedly_payment_method_attributes(update_params)
    )

    ActiveRecord::Base.transaction do
      if update_params.key?(:is_default) && ActiveModel::Type::Boolean.new.cast(update_params[:is_default])
        current_user.payment_methods.update_all(is_default: false)
      end

      @payment_method.update!(
        cardholder_name: spreadly_updated["full_name"],
        exp_month: spreadly_updated["month"] || @payment_method.exp_month,
        exp_year: spreadly_updated["year"] || @payment_method.exp_year,
        last_updated_via_spreedly_at: Time.current,
        is_default: update_params[:is_default].nil? ? @payment_method.is_default : ActiveModel::Type::Boolean.new.cast(update_params[:is_default])
      )
    end

    render_success(data: serialize_payment_method(@payment_method, spreedly_payment_method: spreadly_updated), message: "Payment method updated successfully", status: :ok)
  rescue ActiveRecord::RecordInvalid => e
    render_error(errors: e.record.errors.full_messages, status: :unprocessable_entity)
  rescue Spreedly::Error => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def set_default
    ActiveRecord::Base.transaction do
      current_user.payment_methods.update_all(is_default: false)
      @payment_method.update!(is_default: true)
    end

    render_success(data: serialize_payment_method(@payment_method, spreedly_payment_method: spreedly_payment_method_snapshot(@payment_method)), message: "Default payment method updated", status: :ok)
  end

  def destroy
    deleted_default = @payment_method.is_default?
    begin
      if @payment_method.vault_token.present?
        Spreedly::PaymentMethodsService.new.redact_payment_method(token: @payment_method.vault_token)
      end
    rescue Spreedly::Error => e
      # If card is already absent in Spreedly, delete local record anyway.
      raise e unless spreedly_payment_method_missing?(e)
    end

    @payment_method.update!(spreedly_redacted_at: Time.current, vault_token: nil)
    @payment_method.destroy!

    if deleted_default
      next_payment_method = current_user.payment_methods.order(created_at: :desc).first
      next_payment_method&.update!(is_default: true)
    end

    render_success(message: "Payment method deleted successfully", status: :ok)
  end

  private

  def set_payment_method
    @payment_method = current_user.payment_methods.find_by(id: params[:id])
    return if @payment_method.present?

    render_error(message: "Payment method not found", status: :not_found)
  end

  def create_params
    params.require(:payment_method).permit(
      :provider,
      :vault_token,
      :last4,
      :card_brand,
      :exp_month,
      :exp_year,
      :cardholder_name,
      :billing_email,
      :billing_phone_number,
      :billing_company,
      :billing_address1,
      :billing_address2,
      :billing_city,
      :billing_state,
      :billing_zip,
      :billing_country,
      :shipping_address1,
      :shipping_address2,
      :shipping_city,
      :shipping_state,
      :shipping_zip,
      :shipping_country,
      :shipping_phone_number,
      :is_default,
      billing_address: {},
      shipping_address: {}
    )
  end

  def update_params
    params.require(:payment_method).permit(
      :cardholder_name,
      :is_default,
      :billing_email,
      :billing_phone_number,
      :billing_company,
      :billing_address1,
      :billing_address2,
      :billing_city,
      :billing_state,
      :billing_zip,
      :billing_country,
      :shipping_address1,
      :shipping_address2,
      :shipping_city,
      :shipping_state,
      :shipping_zip,
      :shipping_country,
      :shipping_phone_number,
      billing_address: {},
      shipping_address: {},
      metadata: {}
    )
  end

  def spreedly_payment_method_attributes(permitted_params)
    source = permitted_params.respond_to?(:to_h) ? permitted_params.to_h.deep_symbolize_keys : {}
    billing = extract_address(source, :billing)
    shipping = extract_address(source, :shipping)

    {
      full_name: source[:cardholder_name],
      email: source[:billing_email],
      phone_number: source[:billing_phone_number],
      company: source[:billing_company],
      address1: billing[:address1],
      address2: billing[:address2],
      city: billing[:city],
      state: billing[:state],
      zip: billing[:zip],
      country: billing[:country],
      shipping_address1: shipping[:address1],
      shipping_address2: shipping[:address2],
      shipping_city: shipping[:city],
      shipping_state: shipping[:state],
      shipping_zip: shipping[:zip],
      shipping_country: shipping[:country],
      shipping_phone_number: source[:shipping_phone_number].presence || shipping[:phone_number],
      metadata: source[:metadata]
    }.compact_blank
  end

  def extract_address(source, prefix)
    direct_address = source["#{prefix}_address".to_sym].is_a?(Hash) ? source["#{prefix}_address".to_sym] : {}

    {
      address1: source["#{prefix}_address1".to_sym].presence || direct_address[:address1].presence || direct_address[:line1].presence || direct_address[:street].presence,
      address2: source["#{prefix}_address2".to_sym].presence || direct_address[:address2].presence || direct_address[:line2].presence,
      city: source["#{prefix}_city".to_sym].presence || direct_address[:city].presence,
      state: source["#{prefix}_state".to_sym].presence || direct_address[:state].presence || direct_address[:province].presence || direct_address[:region].presence,
      zip: source["#{prefix}_zip".to_sym].presence || direct_address[:zip].presence || direct_address[:postal_code].presence,
      country: source["#{prefix}_country".to_sym].presence || direct_address[:country].presence || direct_address[:country_code].presence,
      phone_number: direct_address[:phone_number].presence
    }.compact_blank
  end

  def serialize_payment_method(payment_method, spreedly_payment_method: {})
    billing = serialize_address(spreedly_payment_method)
    shipping = serialize_address(spreedly_payment_method, shipping: true)

    {
      id: payment_method.id,
      provider: payment_method.provider,
      card_brand: payment_method.card_brand,
      last4: payment_method.last4,
      exp_month: payment_method.exp_month,
      exp_year: payment_method.exp_year,
      cardholder_name: payment_method.cardholder_name,
      is_default: payment_method.is_default,
      created_at: payment_method.created_at,
      updated_at: payment_method.updated_at,
      vault_token: payment_method.vault_token,
      spreedly_redacted_at: payment_method.spreedly_redacted_at,
      last_updated_via_spreedly_at: payment_method.last_updated_via_spreedly_at,
      billing_address: billing,
      shipping_address: shipping,
      billing_email: spreedly_payment_method["email"],
      billing_phone_number: spreedly_payment_method["phone_number"],
      billing_company: spreedly_payment_method["company"]
    }.compact_blank
  end

  def serialize_address(spreedly_payment_method, shipping: false)
    address = {
      address1: spreedly_payment_method[shipping ? "shipping_address1" : "address1"],
      address2: spreedly_payment_method[shipping ? "shipping_address2" : "address2"],
      city: spreedly_payment_method[shipping ? "shipping_city" : "city"],
      state: spreedly_payment_method[shipping ? "shipping_state" : "state"],
      zip: spreedly_payment_method[shipping ? "shipping_zip" : "zip"],
      country: spreedly_payment_method[shipping ? "shipping_country" : "country"]
    }
    address[:phone_number] = spreedly_payment_method["shipping_phone_number"] if shipping
    address.compact_blank
  end

  def spreedly_payment_method_snapshot(payment_method)
    return {} if payment_method.vault_token.blank?

    Spreedly::PaymentMethodsService.new.get_payment_method(token: payment_method.vault_token)
  rescue Spreedly::Error => e
    Rails.logger.warn("Failed to fetch Spreedly payment method #{payment_method.vault_token}: #{e.message}")
    {}
  end

  def spreedly_payment_method_missing?(error)
    message = error.message.to_s.downcase
    return true if message.include?("unable to find the specified payment method")
    return true if message.include?("payment method not found")

    error.status.to_i == 404
  end
end
