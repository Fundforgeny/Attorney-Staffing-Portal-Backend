# app/controllers/api/v1/payments_controller.rb
class Api::V1::PaymentsController < ActionController::API
  include ApiResponse
  def checkout
    ActiveRecord::Base.transaction do
      first_name = params[:user][:name].split(" ")[0]
      last_name = params[:user][:name].split(" ")[1]
      email = params[:user][:email]
      # 1. Create or find user
      user = User.find_or_create_by!(email: email) do |u|
        u.first_name = first_name
        u.last_name = last_name
      end

      # 2. Handle Stripe Customer
      customer = ensure_stripe_customer(user)

      # 3. Attach and save PaymentMethod
      payment_method = create_payment_method(user, customer, params[:payment_method])

      # 4. Create Plan record (instance of selected plan)
      plan = create_plan_instance(user, params[:plan])

      # 5. Create all Payments (down + monthly)
      payments = create_payment_schedule(plan, payment_method, params[:plan])

      # 6. Charge down payment immediately if exists
      down_payment_record = payments.find { |p| p.down_payment? }
      if down_payment_record && down_payment_record.payment_amount > 0
        charge_down_payment(down_payment_record, customer.id)
      end

      render_success(
        data: {
          user_id: user.id,
          plan_id: plan.id,
          payments: payments.map { |p| payment_serializer(p) }
        },
        message: "Checkout completed successfully",
        status: :created
      )
    end
  rescue StandardError => e
    render_error(message: e.message)
  end

  private

  def ensure_stripe_customer(user)
    if user.stripe_customer_id.present?
      Stripe::Customer.retrieve(user.stripe_customer_id)
    else
      customer = Stripe::Customer.create(
        email: user.email,
        name: user.first_name + " " + user.last_name
      )
      user.update!(stripe_customer_id: customer.id)
      customer
    end
  end

  def create_payment_method(user, customer, pm_params)
    stripe_pm_id = pm_params[:stripe_payment_method_id]

    # Attach to customer
    Stripe::PaymentMethod.attach(stripe_pm_id, customer: customer.id)

    # Set as default (optional)
    Stripe::Customer.update(customer.id, invoice_settings: { default_payment_method: stripe_pm_id })

    # Retrieve for metadata
    stripe_pm = Stripe::PaymentMethod.retrieve(stripe_pm_id)

    PaymentMethod.create!(
      user: user,
      provider: "stripe",
      stripe_payment_method_id: stripe_pm.id,
      vault_token: pm_params[:vault_token], # if you still use external vault
      last4: stripe_pm.card.last4,
      card_brand: stripe_pm.card.brand,
      exp_month: stripe_pm.card.exp_month,
      exp_year: stripe_pm.card.exp_year,
      cardholder_name: stripe_pm.billing_details.name.presence || user.first_name + " " + user.last_name
    )
  end

  def create_plan_instance(user, plan_params)
    Plan.create!(
      user: user,
      name: plan_params[:name], # e.g., "6 Months Plan"
      duration: plan_params[:duration], # in months
      total_payment: plan_params[:total_payment],
      total_interest_amount: plan_params[:total_interest_amount],
      monthly_payment: plan_params[:monthly_payment],
      monthly_interest_amount: plan_params[:monthly_interest_amount],
      down_payment: plan_params[:down_payment],
      status: :active
    )
  end

  def create_payment_schedule(plan, payment_method, plan_params)
    payments = []

    # Down payment (if any)
    if plan_params[:down_payment].to_d > 0
      payments << Payment.create!(
        plan: plan,
        user: plan.user,
        payment_method: payment_method,
        payment_type: :down_payment,
        payment_amount: plan_params[:down_payment],
        status: :pending,
        scheduled_at: Time.current
      )
    end

    # Monthly installments
    start_date = plan_params[:first_installment_date].present? ?
                  Date.parse(plan_params[:first_installment_date]) :
                  Date.today.next_month.beginning_of_month

    plan.duration.times do |i|
      scheduled_date = start_date + i.months

      payments << Payment.create!(
        plan: plan,
        user: plan.user,
        payment_method: payment_method,
        payment_type: :monthly_payment,
        payment_amount: plan_params[:monthly_payment],
        status: :pending,
        scheduled_at: scheduled_date
      )
    end

    payments
  end

  def charge_down_payment(payment_record, stripe_customer_id)
    intent = Stripe::PaymentIntent.create(
      amount: (payment_record.payment_amount * 100).to_i,
      currency: 'usd',
      customer: stripe_customer_id,
      payment_method: payment_record.payment_method.stripe_payment_method_id,
      off_session: false,
      confirm: true,
      description: "Down payment for #{payment_record.plan.name}"
    )

    if intent.status == 'succeeded'
      payment_record.update!(
        status: :succeeded,
        stripe_charge_id: intent.id,
        paid_at: Time.current
      )
    else
      payment_record.update!(status: :failed)
      raise "Down payment failed: #{intent.last_payment_error&.message}"
    end
  end

  def payment_serializer(payment)
    {
      id: payment.id,
      type: payment.payment_type,
      amount: payment.payment_amount,
      status: payment.status,
      scheduled_at: payment.scheduled_at,
      paid_at: payment.paid_at
    }
  end
end
