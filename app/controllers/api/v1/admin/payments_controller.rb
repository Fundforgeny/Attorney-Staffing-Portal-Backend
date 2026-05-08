# Api::V1::Admin::PaymentsController
#
# Full payment management for the admin portal.
#
class Api::V1::Admin::PaymentsController < Api::V1::Admin::BaseController

  before_action :set_payment, only: [:show, :charge_now, :refund]

  # GET /api/v1/admin/payments
  def index
    scope = Payment.includes(plan: :user, payment_method: []).order(created_at: :desc)

    scope = scope.where(status: params[:status])                    if params[:status].present?
    scope = scope.where(payment_type: params[:payment_type])        if params[:payment_type].present?
    scope = scope.where(needs_new_card: true)                       if params[:needs_card] == "true"
    scope = scope.where("retry_count > 0")                         if params[:has_retries] == "true"
    scope = scope.where("next_retry_at <= ?", Date.today)           if params[:retry_due] == "true"
    scope = scope.refunded                                          if params[:refunded] == "true"
    scope = apply_transaction_date_filter(scope)

    if params[:q].present?
      like_query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
      scope = scope.joins(plan: :user)
                   .where(
                     "users.email ILIKE ? OR users.first_name ILIKE ? OR users.last_name ILIKE ? OR users.phone ILIKE ? OR payments.charge_id ILIKE ? OR payments.refund_transaction_id ILIKE ?",
                     like_query, like_query, like_query, like_query, like_query, like_query
                   )
    end

    paged = paginate(scope)

    render_success(
      data: paged.map { |p| payment_row(p) },
      meta: pagination_meta(paged)
    )
  end

  # GET /api/v1/admin/payments/:id
  def show
    render_success(data: payment_full(@payment))
  end

  # POST /api/v1/admin/payments/:id/charge_now
  def charge_now
    ChargePaymentWorker.perform_async(@payment.id)
    render_success(message: "Payment ##{@payment.id} queued for immediate charge.")
  end

  # POST /api/v1/admin/payments/:id/refund
  def refund
    return render_error(message: "You do not have permission to issue refunds.", status: :forbidden) unless current_admin.can_refund_payments?

    Admin::PaymentRefundService.new(
      payment: @payment,
      admin_user: current_admin,
      amount: params[:amount],
      reason: params[:reason]
    ).call

    @payment.reload
    render_success(
      message: "Refund submitted successfully.",
      data: payment_full(@payment)
    )
  rescue ArgumentError, StandardError => e
    render_error(message: "Refund failed: #{e.message}", status: :unprocessable_entity)
  end

  private

  def apply_transaction_date_filter(scope)
    from = parse_date_param(params[:from])
    to = parse_date_param(params[:to])
    return scope unless from || to

    transaction_date_sql = "COALESCE(payments.paid_at, payments.scheduled_at, payments.created_at)"
    scope = scope.where("#{transaction_date_sql} >= ?", from.beginning_of_day) if from
    scope = scope.where("#{transaction_date_sql} <= ?", to.end_of_day) if to
    scope
  end

  def parse_date_param(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def set_payment
    @payment = Payment.includes(plan: :user, payment_method: []).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error(message: "Payment not found.", status: :not_found)
  end

  def payment_row(p)
    {
      id:                  p.id,
      plan_id:             p.plan_id,
      plan_name:           p.plan&.name,
      client_name:         p.plan&.user&.full_name,
      client_email:        p.plan&.user&.email,
      amount:              p.payment_amount.to_f,
      total_amount:        p.total_payment_including_fee.to_f,
      refundable_amount:   p.refundable_amount.to_f,
      refunded_amount:     p.refunded_amount.to_f,
      charge_id:           p.charge_id,
      refund_transaction_id: p.refund_transaction_id,
      refunded_at:         p.refunded_at,
      last_refund_reason:  p.last_refund_reason,
      status:              p.status,
      payment_type:        p.payment_type,
      scheduled_at:        p.scheduled_at,
      paid_at:             p.paid_at,
      retry_count:         p.retry_count || 0,
      next_retry_at:       p.next_retry_at,
      decline_reason:      p.decline_reason,
      needs_new_card:      p.needs_new_card?,
      card_brand:          p.payment_method&.card_brand,
      card_last4:          p.payment_method&.last4,
      created_at:          p.created_at
    }
  end

  def payment_full(p)
    payment_row(p).merge(
      last_attempt_at: p.last_attempt_at,
      plan: {
        id:              p.plan&.id,
        name:            p.plan&.name,
        status:          p.plan&.status,
        monthly_payment: p.plan&.monthly_payment.to_f,
        next_payment_at: p.plan&.next_payment_at
      },
      client: p.plan&.user ? {
        id:    p.plan.user.id,
        name:  p.plan.user.full_name,
        email: p.plan.user.email,
        phone: p.plan.user.phone
      } : nil
    )
  end
end
