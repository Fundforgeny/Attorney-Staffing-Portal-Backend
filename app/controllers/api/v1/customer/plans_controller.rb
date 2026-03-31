# Api::V1::Customer::PlansController
#
# Customer-facing plan endpoints: terms summary and invoice list.
#
class Api::V1::Customer::PlansController < ActionController::API
  include ApiResponse
  before_action :authenticate_customer!
  before_action :set_plan

  # GET /api/v1/customer/plans/:id/terms
  # Returns the full payment terms for a plan in a human-readable structure.
  def terms
    plan = @plan
    user = plan.user

    render_success(data: {
      plan_id:              plan.id,
      plan_name:            plan.name,
      client_name:          user&.full_name,
      status:               plan.status,
      total_legal_fee:      plan.total_payment.to_d,
      administration_fee:   plan.total_interest_amount.to_d,
      total_plan_amount:    (plan.total_payment.to_d + plan.total_interest_amount.to_d),
      down_payment:         plan.down_payment.to_d,
      monthly_payment:      plan.monthly_payment.to_d,
      duration_months:      plan.duration,
      next_payment_date:    plan.next_payment_at,
      remaining_balance:    plan.remaining_balance_logic.to_d,
      payment_schedule:     payment_schedule(plan),
      created_at:           plan.created_at
    })
  end

  # GET /api/v1/customer/plans/:id/invoices
  # Returns a list of invoice-style objects for every succeeded payment.
  def invoices
    payments = @plan.payments
      .where(status: Payment.statuses[:succeeded])
      .order(paid_at: :desc)

    render_success(data: payments.map { |p| serialize_invoice(p) })
  end

  private

  def authenticate_customer!
    token = request.headers["Authorization"]&.split(" ")&.last
    return render_error(message: "Unauthorized", status: :unauthorized) unless token.present?

    payload = Warden::JWTAuth::TokenDecoder.new.call(token)
    @current_customer = User.find_by(id: payload["sub"])
    render_error(message: "Unauthorized", status: :unauthorized) unless @current_customer
  rescue JWT::DecodeError, Warden::JWTAuth::Errors::RevokedToken
    render_error(message: "Session expired. Please log in again.", status: :unauthorized)
  end

  def current_customer
    @current_customer
  end

  def set_plan
    @plan = current_customer.plans.find_by(id: params[:id])
    render_error(message: "Plan not found", status: :not_found) unless @plan
  end

  def payment_schedule(plan)
    plan.payments
        .where(payment_type: [:monthly_payment, :full_payment])
        .order(scheduled_at: :asc)
        .map do |p|
          {
            id:           p.id,
            amount:       p.payment_amount.to_d,
            scheduled_at: p.scheduled_at,
            status:       p.status,
            paid_at:      p.paid_at
          }
        end
  end

  def serialize_invoice(payment)
    plan = payment.plan
    user = payment.user
    pm   = payment.payment_method

    {
      invoice_number:  "INV-#{payment.id.to_s.rjust(6, '0')}",
      plan_name:       plan&.name,
      client_name:     user&.full_name,
      client_email:    user&.email,
      amount:          payment.payment_amount.to_d,
      fee:             payment.transaction_fee.to_d,
      total:           payment.total_payment_including_fee.to_d,
      payment_type:    payment.payment_type.humanize,
      payment_method:  pm ? "#{pm.card_brand&.upcase} ••••#{pm.last4}" : "Card on file",
      transaction_id:  payment.charge_id,
      paid_at:         payment.paid_at,
      status:          payment.status
    }
  end
end
