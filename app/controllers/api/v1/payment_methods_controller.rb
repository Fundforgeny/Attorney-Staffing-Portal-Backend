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
    render_success(data: serialize_payment_method(@payment_method), status: :ok)
  end

  def create
    payment_method = current_user.payment_methods.new(create_params)

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
    ActiveRecord::Base.transaction do
      if update_params.key?(:is_default) && ActiveModel::Type::Boolean.new.cast(update_params[:is_default])
        current_user.payment_methods.update_all(is_default: false)
      end

      @payment_method.update!(update_params)
    end

    render_success(data: serialize_payment_method(@payment_method), message: "Payment method updated successfully", status: :ok)
  rescue ActiveRecord::RecordInvalid => e
    render_error(errors: e.record.errors.full_messages, status: :unprocessable_entity)
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
      :stripe_payment_method_id,
      :vault_token,
      :last4,
      :card_brand,
      :exp_month,
      :exp_year,
      :cardholder_name,
      :is_default,
      :card_number,
      :card_cvc
    )
  end

  def update_params
    params.require(:payment_method).permit(
      :provider,
      :stripe_payment_method_id,
      :vault_token,
      :last4,
      :card_brand,
      :exp_month,
      :exp_year,
      :cardholder_name,
      :is_default,
      :card_number,
      :card_cvc
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
      is_default: payment_method.is_default,
      created_at: payment_method.created_at,
      updated_at: payment_method.updated_at,
      card_number: payment_method.card_number,
      card_cvc: payment_method.card_cvc
    }
  end
end



