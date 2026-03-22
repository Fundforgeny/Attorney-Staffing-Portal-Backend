class Api::V1::PaymentMethodsController < ActionController::API
  include ApiResponse
  include Devise::Controllers::Helpers
  include PaymentMethodContactFields

  before_action :authenticate_user!
  before_action :set_payment_method, only: [ :show, :update, :destroy, :set_default ]

  def index
    payment_methods = current_user.payment_methods.ordered_for_user
    render_success(data: payment_methods.map { |payment_method| serialize_payment_method(payment_method) }, status: :ok)
  end

  def show
    render_success(data: serialize_payment_method(@payment_method), status: :ok)
  end

  def create
    if create_params[:vault_token].blank?
      return render_error(message: "vault_token is required", status: :bad_request)
    end

    payment_method = current_user.payment_methods.new(
      provider: create_params[:provider].presence || "Spreedly Vault",
      vault_token: create_params[:vault_token],
      last4: create_params[:last4],
      card_brand: create_params[:card_brand],
      exp_month: create_params[:exp_month],
      exp_year: create_params[:exp_year],
      cardholder_name: create_params[:cardholder_name],
      billing_email: create_params[:billing_email],
      billing_phone: create_params[:billing_phone],
      billing_address1: create_params[:billing_address1],
      billing_address2: create_params[:billing_address2],
      billing_city: create_params[:billing_city],
      billing_state: create_params[:billing_state],
      billing_zip: create_params[:billing_zip],
      billing_country: create_params[:billing_country],
      last_updated_via_spreedly_at: Time.current
    )

    ActiveRecord::Base.transaction do
      if ActiveModel::Type::Boolean.new.cast(create_params[:is_default]) || current_user.payment_methods.blank?
        current_user.payment_methods.update_all(is_default: false)
        payment_method.is_default = true
      end
      payment_method.save!
    end

    render_success(
      data: serialize_payment_method(payment_method),
      message: "Payment method added successfully",
      status: :created
    )
  rescue ActiveRecord::RecordInvalid => e
    render_error(errors: e.record.errors.full_messages, status: :unprocessable_entity)
  end

  def update
    spreedly = Spreedly::PaymentMethodsService.new
    spreadly_updated = spreedly.update_payment_method(
      token: @payment_method.vault_token,
      **extract_payment_method_contact_attrs(update_params),
      metadata: update_params[:metadata]
    )

    ActiveRecord::Base.transaction do
      if update_params.key?(:is_default) && ActiveModel::Type::Boolean.new.cast(update_params[:is_default])
        current_user.payment_methods.update_all(is_default: false)
      end

      @payment_method.update!(
        cardholder_name: spreadly_updated["full_name"].presence || @payment_method.cardholder_name,
        billing_email: spreadly_updated["email"].presence || update_params[:billing_email] || @payment_method.billing_email,
        billing_phone: spreadly_updated["phone_number"].presence || update_params[:billing_phone] || @payment_method.billing_phone,
        billing_address1: spreadly_updated["address1"].presence || update_params[:billing_address1] || @payment_method.billing_address1,
        billing_address2: spreadly_updated["address2"].presence || update_params[:billing_address2] || @payment_method.billing_address2,
        billing_city: spreadly_updated["city"].presence || update_params[:billing_city] || @payment_method.billing_city,
        billing_state: spreadly_updated["state"].presence || update_params[:billing_state] || @payment_method.billing_state,
        billing_zip: spreadly_updated["zip"].presence || update_params[:billing_zip] || @payment_method.billing_zip,
        billing_country: spreadly_updated["country"].presence || update_params[:billing_country] || @payment_method.billing_country,
        exp_month: spreadly_updated["month"] || @payment_method.exp_month,
        exp_year: spreadly_updated["year"] || @payment_method.exp_year,
        last_updated_via_spreedly_at: Time.current,
        is_default: update_params[:is_default].nil? ? @payment_method.is_default : ActiveModel::Type::Boolean.new.cast(update_params[:is_default])
      )
    end

    render_success(data: serialize_payment_method(@payment_method), message: "Payment method updated successfully", status: :ok)
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

    render_success(data: serialize_payment_method(@payment_method), message: "Default payment method updated", status: :ok)
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
      :billing_phone,
      :billing_address1,
      :billing_address2,
      :billing_city,
      :billing_state,
      :billing_zip,
      :billing_country,
      :is_default
    )
  end

  def update_params
    params.require(:payment_method).permit(
      :cardholder_name,
      :is_default,
      :billing_email,
      :billing_phone,
      :billing_address1,
      :billing_address2,
      :billing_city,
      :billing_state,
      :billing_zip,
      :billing_country,
      metadata: {}
    )
  end

  def serialize_payment_method(payment_method)
    {
      id: payment_method.id,
      provider: payment_method.provider,
      card_brand: payment_method.card_brand,
      last4: payment_method.last4,
      exp_month: payment_method.exp_month,
      exp_year: payment_method.exp_year,
      cardholder_name: payment_method.cardholder_name,
      billing_email: payment_method.billing_email,
      billing_phone: payment_method.billing_phone,
      billing_address1: payment_method.billing_address1,
      billing_address2: payment_method.billing_address2,
      billing_city: payment_method.billing_city,
      billing_state: payment_method.billing_state,
      billing_zip: payment_method.billing_zip,
      billing_country: payment_method.billing_country,
      is_default: payment_method.is_default,
      created_at: payment_method.created_at,
      updated_at: payment_method.updated_at,
      vault_token: payment_method.vault_token,
      spreedly_redacted_at: payment_method.spreedly_redacted_at,
      last_updated_via_spreedly_at: payment_method.last_updated_via_spreedly_at
    }
  end

  def spreedly_payment_method_missing?(error)
    message = error.message.to_s.downcase
    return true if message.include?("unable to find the specified payment method")
    return true if message.include?("payment method not found")

    error.status.to_i == 404
  end
end



