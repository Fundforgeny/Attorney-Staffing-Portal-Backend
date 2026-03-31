# Api::V1::Admin::PaymentsController
#
# Full payment management for the admin portal.
#
class Api::V1::Admin::PaymentsController < Api::V1::Admin::BaseController

  before_action :set_payment, only: [:show, :charge_now]

  # GET /api/v1/admin/payments
  def index
    scope = Payment.includes(plan: :user, payment_method: []).order(created_at: :desc)

    scope = scope.where(status: params[:status])                    if params[:status].present?
    scope = scope.where(payment_type: params[:payment_type])        if params[:payment_type].present?
    scope = scope.where(needs_new_card: true)                       if params[:needs_card] == "true"
    scope = scope.where("retry_count > 0")                         if params[:has_retries] == "true"
    scope = scope.where("next_retry_at <= ?", Date.today)           if params[:retry_due] == "true"
    scope = scope.where("scheduled_at >= ?", params[:from].to_date) if params[:from].present?
    scope = scope.where("scheduled_at <= ?", params[:to].to_date)   if params[:to].present?

    if params[:q].present?
      scope = scope.joins(plan: :user)
                   .where("users.email ILIKE ? OR users.first_name ILIKE ? OR users.last_name ILIKE ?",
                          "%#{params[:q]}%", "%#{params[:q]}%", "%#{params[:q]}%")
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

  private

  def set_payment
    @payment = Payment.includes(plan: :user, payment_method: []).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error(message: "Payment not found.", status: :not_found)
  end

  def payment_row(p)
    {
      id:              p.id,
      plan_id:         p.plan_id,
      plan_name:       p.plan&.name,
      client_name:     p.plan&.user&.full_name,
      client_email:    p.plan&.user&.email,
      amount:          p.amount.to_f,
      status:          p.status,
      payment_type:    p.payment_type,
      scheduled_at:    p.scheduled_at,
      paid_at:         p.paid_at,
      retry_count:     p.retry_count || 0,
      next_retry_at:   p.next_retry_at,
      decline_reason:  p.decline_reason,
      needs_new_card:  p.needs_new_card?,
      card_brand:      p.payment_method&.card_brand,
      card_last4:      p.payment_method&.last4,
      created_at:      p.created_at
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
