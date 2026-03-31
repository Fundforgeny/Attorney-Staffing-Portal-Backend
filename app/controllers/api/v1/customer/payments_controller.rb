# Api::V1::Customer::PaymentsController
#
# Customer-facing payment endpoints. All actions require a valid JWT session
# (magic link login). Clients can only see and act on their own data.
#
class Api::V1::Customer::PaymentsController < ActionController::API
  include ApiResponse
  before_action :authenticate_customer!
  before_action :set_plan, only: [:history, :manual_payment]

  # GET /api/v1/customer/plans/:plan_id/payments
  # Returns the full payment history for a plan, including retry metadata.
  def history
    payments = @plan.payments
      .order(scheduled_at: :asc, created_at: :asc)
      .map { |p| serialize_payment(p) }

    render_success(data: payments)
  end

  # POST /api/v1/customer/plans/:plan_id/payments/manual
  # Client makes a manual payment toward their installment using their card on file.
  # Accepts an optional `amount` param; defaults to the plan's monthly_payment.
  # A partial payment (amount < installment) is accepted but does NOT stop retries.
  def manual_payment
    amount = params[:amount].present? ? params[:amount].to_d : @plan.monthly_payment.to_d

    if amount <= 0
      return render_error(message: "Amount must be greater than zero", status: :unprocessable_entity)
    end

    payment_method = resolve_payment_method
    unless payment_method&.vault_token.present?
      return render_error(
        message: "No card on file. Please add a payment method before making a payment.",
        status: :unprocessable_entity
      )
    end

    result = ManualPortalPaymentService.new(
      plan:           @plan,
      payment_method: payment_method,
      amount:         amount,
      user:           current_customer
    ).call

    if result[:success]
      render_success(
        data:    serialize_payment(result[:payment]),
        message: "Payment of #{format_currency(amount)} processed successfully."
      )
    else
      render_error(
        message: result[:error] || "Payment failed. Please try again or contact support.",
        status:  :unprocessable_entity
      )
    end
  rescue StandardError => e
    Rails.logger.error("[Customer::PaymentsController] manual_payment error: #{e.class}: #{e.message}")
    render_error(message: "An unexpected error occurred.", status: :internal_server_error)
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

  def current_customer
    @current_customer
  end

  def set_plan
    @plan = current_customer.plans.find_by(id: params[:plan_id])
    unless @plan
      render_error(message: "Plan not found", status: :not_found)
    end
  end

  def resolve_payment_method
    pm_id = params[:payment_method_id]
    if pm_id.present?
      current_customer.payment_methods.find_by(id: pm_id)
    else
      current_customer.payment_methods.ordered_for_user.first
    end
  end

  def serialize_payment(payment)
    {
      id:                          payment.id,
      payment_type:                payment.payment_type,
      amount:                      payment.payment_amount.to_d,
      transaction_fee:             payment.transaction_fee.to_d,
      total:                       payment.total_payment_including_fee.to_d,
      status:                      payment.status,
      scheduled_at:                payment.scheduled_at,
      paid_at:                     payment.paid_at,
      retry_count:                 payment.retry_count.to_i,
      last_attempt_at:             payment.last_attempt_at,
      next_retry_at:               payment.next_retry_at,
      decline_reason:              humanize_decline_reason(payment.decline_reason),
      needs_new_card:              payment.needs_new_card?,
      covered_by_manual_payment:   payment.decline_reason.to_s.start_with?("covered_by_payment_id_")
    }
  end

  def humanize_decline_reason(reason)
    return nil if reason.blank?
    return nil if reason.start_with?("covered_by_payment_id_")

    case reason
    when "no_vault_token"    then "No card on file"
    when "covered_by_manual_payment" then nil
    else reason.humanize
    end
  end

  def format_currency(amount)
    "$#{format('%.2f', amount)}"
  end
end
