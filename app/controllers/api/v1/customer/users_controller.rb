# Api::V1::Customer::UsersController
#
# Customer-facing user endpoints. Returns the authenticated customer's own data.
#
class Api::V1::Customer::UsersController < ActionController::API
  include ApiResponse
  before_action :authenticate_customer!

  # GET /api/v1/customer/me
  # Returns the current customer's profile, plans, and agreements.
  def me
    user = User.includes(:payment_method, :firm, :firms, agreements: :plan, plans: [:agreement, :payments]).find(@current_customer.id)
    render_success(data: serialized_user(user))
  end

  private

  def authenticate_customer!
    token = request.headers["Authorization"]&.split(" ")&.last
    unless token.present?
      return render_error(message: "Unauthorized", status: :unauthorized)
    end

    payload = Warden::JWTAuth::TokenDecoder.new.call(token)
    @current_customer = User.find_by(id: payload["sub"])

    unless @current_customer
      render_error(message: "Unauthorized", status: :unauthorized)
    end
  rescue JWT::DecodeError, Warden::JWTAuth::Errors::RevokedToken
    render_error(message: "Session expired. Please log in again.", status: :unauthorized)
  end

  def serialized_user(user)
    {
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      phone: user.phone,
      user_type: user.user_type,
      firm_id: user.firm_id,
      payment_method: serialized_payment_method(user.payment_method),
      primary_firm: serialized_firm(user.firm),
      firms: user.firms.map { |firm| serialized_firm(firm) },
      plans: customer_visible_plans(user).map { |plan| serialized_plan(plan) },
      agreements: user.agreements.map { |agreement| serialized_agreement(agreement) }
    }
  end

  def serialized_plan(plan)
    {
      id: plan.id,
      name: plan.name,
      status: customer_facing_plan_status(plan),
      duration: plan.duration,
      total_payment: plan.total_payment,
      down_payment: plan.down_payment,
      monthly_payment: plan.monthly_payment,
      total_interest_amount: plan.total_interest_amount,
      monthly_interest_amount: plan.monthly_interest_amount,
      base_legal_fee: plan.base_legal_fee_amount,
      payment_plan_selected: plan.payment_plan_selected?,
      next_payment_at: plan.next_payment_at,
      administration_fee_name: plan.administration_fee_name,
      administration_fee_percentage: plan.administration_fee_percentage,
      administration_fee_amount: plan.administration_fee_amount,
      total_payment_plan_amount: plan.total_payment_plan_amount,
      paid_amount: plan.payments.where(status: :succeeded).sum(:total_payment_including_fee).to_d,
      remaining_balance: plan.remaining_balance_logic.to_d,
      created_at: plan.created_at,
      updated_at: plan.updated_at,
      payments: plan.payments.map { |payment| serialized_payment(payment) },
      agreement: serialized_agreement(plan.agreement)
    }
  end

  def customer_visible_plans(user)
    user.plans.reject(&:draft?)
  end

  def customer_facing_plan_status(plan)
    return "active" if plan.paid?
    return "completed" if plan.expired?
    return "canceled" if plan.failed?
    plan.status
  end

  def serialized_payment(payment)
    {
      id: payment.id,
      plan_id: payment.plan_id,
      payment_method_id: payment.payment_method_id,
      payment_type: payment.payment_type,
      status: payment.status,
      payment_amount: payment.payment_amount,
      total_payment_including_fee: payment.total_payment_including_fee,
      transaction_fee: payment.transaction_fee,
      charge_id: payment.charge_id,
      scheduled_at: payment.scheduled_at,
      paid_at: payment.paid_at,
      created_at: payment.created_at,
      updated_at: payment.updated_at
    }
  end

  def serialized_payment_method(payment_method)
    return nil if payment_method.blank?
    {
      id: payment_method.id,
      provider: payment_method.provider,
      card_brand: payment_method.card_brand,
      last4: payment_method.last4,
      exp_month: payment_method.exp_month,
      exp_year: payment_method.exp_year,
      cardholder_name: payment_method.cardholder_name,
      created_at: payment_method.created_at,
      updated_at: payment_method.updated_at
    }
  end

  def serialized_firm(firm)
    return nil if firm.blank?
    {
      id: firm.id,
      name: firm.name,
      description: firm.description,
      primary_color: firm.primary_color,
      secondary_color: firm.secondary_color,
      location_id: firm.location_id,
      created_at: firm.created_at,
      updated_at: firm.updated_at
    }
  end

  def serialized_agreement(agreement)
    return nil if agreement.blank?
    {
      id: agreement.id,
      user_id: agreement.user_id,
      plan_id: agreement.plan_id,
      signed_at: agreement.signed_at,
      created_at: agreement.created_at,
      updated_at: agreement.updated_at
    }
  end
end
