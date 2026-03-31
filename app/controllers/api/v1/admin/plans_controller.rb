# Api::V1::Admin::PlansController
#
# Full plan management for the admin portal.
#
class Api::V1::Admin::PlansController < Api::V1::Admin::BaseController

  before_action :set_plan, only: [:show, :sync_ghl, :manual_charge, :charge_payment,
                                   :set_default_card, :delete_card,
                                   :approve_grace_week, :deny_grace_week]

  # GET /api/v1/admin/plans
  def index
    scope = Plan.includes(:user).order(created_at: :desc)

    # Filters
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where("plans.name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
    scope = scope.joins(:payments).where(payments: { needs_new_card: true }).distinct if params[:needs_card] == "true"
    scope = scope.where.not(status: :paid) if params[:leads_only] == "true"

    paged = paginate(scope)

    render_success(
      data: paged.map { |p| plan_summary(p) },
      meta: pagination_meta(paged)
    )
  end

  # GET /api/v1/admin/plans/:id
  def show
    user     = @plan.user
    payments = @plan.payments.includes(:payment_method).order(scheduled_at: :asc, created_at: :asc)
    cards    = user&.payment_methods&.ordered_for_user || []
    graces   = @plan.grace_week_requests.order(created_at: :desc)
    agreement = @plan.agreement

    render_success(data: {
      plan:            plan_detail(@plan),
      payments:        payments.map { |p| payment_detail(p) },
      cards:           cards.map { |c| card_detail(c) },
      grace_requests:  graces.map { |g| grace_detail(g) },
      agreement:       agreement ? { id: agreement.id, signed_at: agreement.created_at, pdf_url: agreement.pdf_url } : nil
    })
  end

  # POST /api/v1/admin/plans/:id/sync_ghl
  def sync_ghl
    GhlPlanSyncWorker.new.perform(@plan.id)
    render_success(message: "GHL sync queued.")
  rescue => e
    render_error(message: "GHL sync failed: #{e.message}")
  end

  # POST /api/v1/admin/plans/:id/manual_charge
  def manual_charge
    pm = params[:payment_method_id].present? ?
           @plan.user.payment_methods.find(params[:payment_method_id]) :
           @plan.user.payment_methods.ordered_for_user.first

    raise "No payment method on file" unless pm

    Admin::ManualVaultChargeService.new(
      plan:           @plan,
      amount:         params[:amount],
      description:    params[:description].presence || "Admin manual payment",
      payment_method: pm
    ).call

    render_success(message: "Manual charge of $#{params[:amount]} submitted.")
  rescue => e
    render_error(message: "Manual charge failed: #{e.message}")
  end

  # POST /api/v1/admin/plans/:id/charge_payment
  def charge_payment
    payment = @plan.payments.find(params[:payment_id])
    ChargePaymentWorker.perform_async(payment.id)
    render_success(message: "Payment ##{payment.id} queued for immediate charge.")
  rescue ActiveRecord::RecordNotFound
    render_error(message: "Payment not found.", status: :not_found)
  end

  # POST /api/v1/admin/plans/:id/set_default_card
  def set_default_card
    pm = @plan.user.payment_methods.find(params[:payment_method_id])
    @plan.user.payment_methods.update_all(is_default: false)
    pm.update!(is_default: true)
    render_success(message: "#{pm.card_brand&.upcase} ••••#{pm.last4} set as default.")
  rescue ActiveRecord::RecordNotFound
    render_error(message: "Card not found.", status: :not_found)
  end

  # DELETE /api/v1/admin/plans/:id/delete_card
  def delete_card
    pm = @plan.user.payment_methods.find(params[:payment_method_id])
    begin
      Spreedly::PaymentMethodsService.new.redact_payment_method(token: pm.vault_token) if pm.vault_token.present?
    rescue => e
      Rails.logger.warn("[Admin] Spreedly redact failed for #{pm.vault_token}: #{e.message}")
    end
    pm.destroy!
    render_success(message: "Card removed.")
  rescue ActiveRecord::RecordNotFound
    render_error(message: "Card not found.", status: :not_found)
  end

  # POST /api/v1/admin/plans/:id/approve_grace_week
  def approve_grace_week
    grace = @plan.grace_week_requests.find(params[:grace_week_request_id])
    GraceWeekService.approve!(grace: grace, admin_note: params[:admin_note])
    render_success(message: "Grace week approved. Two half-payments scheduled.")
  rescue GraceWeekService::Error => e
    render_error(message: "Grace week approval failed: #{e.message}")
  end

  # POST /api/v1/admin/plans/:id/deny_grace_week
  def deny_grace_week
    grace = @plan.grace_week_requests.find(params[:grace_week_request_id])
    GraceWeekService.deny!(grace: grace, admin_note: params[:admin_note])
    render_success(message: "Grace week denied.")
  rescue GraceWeekService::Error => e
    render_error(message: "Grace week denial failed: #{e.message}")
  end

  private

  def set_plan
    @plan = Plan.includes(:user, :payments, :grace_week_requests).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error(message: "Plan not found.", status: :not_found)
  end

  def plan_summary(plan)
    {
      id:              plan.id,
      name:            plan.name,
      status:          plan.status,
      duration:        plan.duration,
      total_payment:   plan.total_payment.to_f,
      monthly_payment: plan.monthly_payment.to_f,
      next_payment_at: plan.next_payment_at,
      needs_new_card:  plan.payments.any?(&:needs_new_card?),
      client_name:     plan.user&.full_name,
      client_email:    plan.user&.email,
      created_at:      plan.created_at
    }
  end

  def plan_detail(plan)
    user = plan.user
    {
      id:                       plan.id,
      name:                     plan.name,
      status:                   plan.status,
      duration:                 plan.duration,
      total_payment:            plan.total_payment.to_f,
      total_interest_amount:    plan.total_interest_amount.to_f,
      monthly_payment:          plan.monthly_payment.to_f,
      monthly_interest_amount:  plan.monthly_interest_amount.to_f,
      down_payment:             plan.down_payment.to_f,
      remaining_balance:        plan.remaining_balance_logic.to_f,
      next_payment_at:          plan.next_payment_at,
      created_at:               plan.created_at,
      client: user ? {
        id:         user.id,
        name:       user.full_name,
        email:      user.email,
        phone:      user.phone,
        user_type:  user.user_type
      } : nil
    }
  end

  def payment_detail(payment)
    {
      id:               payment.id,
      amount:           payment.amount.to_f,
      status:           payment.status,
      payment_type:     payment.payment_type,
      scheduled_at:     payment.scheduled_at,
      paid_at:          payment.paid_at,
      retry_count:      payment.retry_count || 0,
      last_attempt_at:  payment.last_attempt_at,
      next_retry_at:    payment.next_retry_at,
      decline_reason:   payment.decline_reason,
      needs_new_card:   payment.needs_new_card?,
      card_brand:       payment.payment_method&.card_brand,
      card_last4:       payment.payment_method&.last4
    }
  end

  def card_detail(pm)
    {
      id:         pm.id,
      card_brand: pm.card_brand,
      last4:      pm.last4,
      exp_month:  pm.exp_month,
      exp_year:   pm.exp_year,
      is_default: pm.is_default?,
      created_at: pm.created_at
    }
  end

  def grace_detail(g)
    {
      id:          g.id,
      status:      g.status,
      reason:      g.reason,
      admin_note:  g.admin_note,
      halves_paid: g.halves_paid,
      created_at:  g.created_at
    }
  end
end
