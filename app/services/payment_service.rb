# app/services/payment_service.rb
class PaymentService
  def initialize(user, plan, payment_params, first_installment_date = nil)
    @user = user
    @plan = plan
    @payment_params = payment_params
    @first_installment_date = first_installment_date
  end

  def process_checkout
    payment_method = store_card_details
    payments = create_payment_schedule(payment_method)
    payments
  end

  private

  def store_card_details
    PaymentMethod.create!(
      user: @user,
      provider: "Spreedly Vault",
      card_number: @payment_params[:number],
      card_cvc: @payment_params[:cvc],
      cardholder_name: "#{@user.first_name} #{@user.last_name}".strip,
      last4: @payment_params[:last_four].to_s,
      exp_month: @payment_params[:exp_month].to_s,
      exp_year: @payment_params[:exp_year].to_s
    )
  end

  def create_payment_schedule(payment_method)
    payments = []
    payments << create_down_payment(payment_method) if @plan.down_payment > 0
    payments.concat(create_monthly_installments(payment_method)) if @plan.duration > 0
    payments
  end

  def create_down_payment(payment_method)
    Payment.create!(
      plan: @plan,
      user: @user,
      payment_method: payment_method,
      payment_type: @plan.duration > 0 ? :down_payment : :full_payment,
      payment_amount: @plan.down_payment,
      total_payment_including_fee: (@plan.down_payment * 1.03).round(2),
      transaction_fee: (@plan.down_payment * 0.03).round(2),
      status: :pending,
      scheduled_at: Time.current
    )
  end

  def create_monthly_installments(payment_method)
    payments = []
    start_date = parse_installment_date

    @plan.duration.times do |i|
      payments << Payment.create!(
        plan: @plan,
        user: @user,
        payment_method: payment_method,
        payment_type: :monthly_payment,
        payment_amount: @plan.monthly_payment,
        total_payment_including_fee: (@plan.monthly_payment * 1.03).round(2),
        transaction_fee: (@plan.monthly_payment * 0.03).round(2),
        status: :pending,
        scheduled_at: start_date + i.months
      )
    end

    payments
  end

  def parse_installment_date
    return Time.current unless @first_installment_date.present?
    
    Time.zone.strptime(@first_installment_date, "%m-%d-%Y")
  rescue ArgumentError
    Time.current
  end
end
