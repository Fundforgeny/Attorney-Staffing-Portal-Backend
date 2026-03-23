# app/services/payment_service.rb
class PaymentService
  def initialize(user, plan, payment_params, first_installment_date = nil)
    @user = user
    @plan = plan
    @payment_params = payment_params
    @first_installment_date = first_installment_date
  end

  def process_checkout
    payment_method = resolve_payment_method!
    payments = create_payment_schedule(payment_method)
    payments
  end

  private

  def resolve_payment_method!
    params = normalized_payment_params

    if params[:payment_method_id].present?
      return @user.payment_methods.find(params[:payment_method_id])
    end

    vault_token = params[:vault_token].presence || params.dig(:payment_method, :vault_token).presence
    if vault_token.present?
      return find_or_create_tokenized_payment_method!(vault_token, params)
    end

    legacy_params = params[:payment_method].is_a?(Hash) ? params[:payment_method] : params
    return store_legacy_card_details(legacy_params) if legacy_card_payload?(legacy_params)

    default_payment_method = @user.payment_methods.ordered_for_user.first
    return default_payment_method if default_payment_method.present?

    raise ArgumentError, "Missing payment method: provide payment_method_id or vault_token"
  end

  def find_or_create_tokenized_payment_method!(vault_token, params)
    sync_spreedly_payment_method!(vault_token, params)

    PaymentMethod.create!(
      user: @user,
      provider: "Spreedly Vault",
      vault_token: vault_token,
      card_brand: params[:card_brand].presence || params.dig(:payment_method, :card_brand),
      cardholder_name: params[:cardholder_name].presence || "#{@user.first_name} #{@user.last_name}".strip,
      last4: params[:last4].presence || params.dig(:payment_method, :last4),
      exp_month: params[:exp_month].presence || params.dig(:payment_method, :exp_month),
      exp_year: params[:exp_year].presence || params.dig(:payment_method, :exp_year),
      is_default: @user.payment_methods.blank?
    )
  end

  # Legacy fallback for older clients that still post raw card fields.
  def sync_spreedly_payment_method!(vault_token, params)
    attributes = spreedly_payment_method_attributes(params)
    return if attributes.blank?

    Spreedly::PaymentMethodsService.new.update_payment_method(token: vault_token, **attributes)
  rescue Spreedly::Error => e
    Rails.logger.warn("Failed to sync Spreedly payment method #{vault_token}: #{e.message}")
  end

  def spreedly_payment_method_attributes(params)
    payment_method = params[:payment_method].is_a?(Hash) ? params[:payment_method] : {}

    {
      full_name: params[:cardholder_name].presence || payment_method[:cardholder_name].presence || "#{@user.first_name} #{@user.last_name}".strip.presence,
      first_name: params[:first_name].presence || payment_method[:first_name].presence || @user.first_name,
      last_name: params[:last_name].presence || payment_method[:last_name].presence || @user.last_name,
      email: params[:billing_email].presence || payment_method[:billing_email].presence || @user.email,
      phone_number: params[:billing_phone_number].presence || payment_method[:billing_phone_number].presence,
      company: params[:billing_company].presence || payment_method[:billing_company].presence,
      address1: params[:billing_address1].presence || payment_method[:billing_address1].presence || params[:address1].presence || payment_method[:address1].presence,
      address2: params[:billing_address2].presence || payment_method[:billing_address2].presence || params[:address2].presence || payment_method[:address2].presence,
      city: params[:billing_city].presence || payment_method[:billing_city].presence || params[:city].presence || payment_method[:city].presence,
      state: params[:billing_state].presence || payment_method[:billing_state].presence || params[:state].presence || payment_method[:state].presence,
      zip: params[:billing_zip].presence || payment_method[:billing_zip].presence || params[:zip].presence || payment_method[:zip].presence,
      country: params[:billing_country].presence || payment_method[:billing_country].presence || params[:country].presence || payment_method[:country].presence,
      shipping_address1: params[:shipping_address1].presence || payment_method[:shipping_address1].presence,
      shipping_address2: params[:shipping_address2].presence || payment_method[:shipping_address2].presence,
      shipping_city: params[:shipping_city].presence || payment_method[:shipping_city].presence,
      shipping_state: params[:shipping_state].presence || payment_method[:shipping_state].presence,
      shipping_zip: params[:shipping_zip].presence || payment_method[:shipping_zip].presence,
      shipping_country: params[:shipping_country].presence || payment_method[:shipping_country].presence,
      shipping_phone_number: params[:shipping_phone_number].presence || payment_method[:shipping_phone_number].presence
    }.compact_blank
  end

  def store_legacy_card_details(legacy_params)
    PaymentMethod.create!(
      user: @user,
      provider: "Spreedly Vault",
      card_number: legacy_params[:number],
      card_cvc: legacy_params[:cvc],
      cardholder_name: "#{@user.first_name} #{@user.last_name}".strip,
      last4: legacy_params[:last_four].to_s,
      exp_month: legacy_params[:exp_month].to_s,
      exp_year: legacy_params[:exp_year].to_s,
      is_default: @user.payment_methods.blank?
    )
  end

  def create_payment_schedule(payment_method)
    # Rebuilding the schedule makes repeated checkout calls idempotent.
    @plan.payments.destroy_all

    payments = []
    payments << create_down_payment(payment_method) if @plan.down_payment > 0
    payments.concat(create_monthly_installments(payment_method)) if @plan.duration > 0
    payments
  end

  def create_down_payment(payment_method)
    amounts = fee_breakdown_for(@plan.down_payment)

    Payment.create!(
      plan: @plan,
      user: @user,
      payment_method: payment_method,
      payment_type: @plan.duration > 0 ? :down_payment : :full_payment,
      payment_amount: @plan.down_payment,
      total_payment_including_fee: amounts[:total],
      transaction_fee: amounts[:fee],
      status: :pending,
      scheduled_at: Time.current
    )
  end

  def create_monthly_installments(payment_method)
    payments = []
    start_date = parse_installment_date

    @plan.duration.times do |i|
      amounts = fee_breakdown_for(@plan.monthly_payment)

      payments << Payment.create!(
        plan: @plan,
        user: @user,
        payment_method: payment_method,
        payment_type: :monthly_payment,
        payment_amount: @plan.monthly_payment,
        total_payment_including_fee: amounts[:total],
        transaction_fee: amounts[:fee],
        status: :pending,
        scheduled_at: start_date + i.months
      )
    end

    payments
  end

  def parse_installment_date
    return Time.current unless @first_installment_date.present?

    date_str = @first_installment_date.to_s.strip
    Time.zone.strptime(date_str, "%Y-%m-%d")
  rescue ArgumentError
    Time.zone.strptime(date_str, "%m-%d-%Y")
  rescue ArgumentError
    Time.current
  end

  def fee_breakdown_for(amount)
    selected_payment_plan = PaymentPlanFeeCalculator.plan_selected?(
      selected_payment_plan: nil,
      duration: @plan.duration
    )
    calculator = PaymentPlanFeeCalculator.new(base_amount: amount, selected_payment_plan: selected_payment_plan)

    {
      fee: calculator.fee_amount,
      total: calculator.total_amount
    }
  end

  def normalized_payment_params
    raw = @payment_params.respond_to?(:to_h) ? @payment_params.to_h : {}
    raw.deep_symbolize_keys
  rescue StandardError
    {}
  end

  def legacy_card_payload?(params)
    params.is_a?(Hash) && params[:number].present? && params[:cvc].present?
  end
end
