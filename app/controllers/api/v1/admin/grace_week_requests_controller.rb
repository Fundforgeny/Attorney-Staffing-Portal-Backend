# Api::V1::Admin::GraceWeekRequestsController
#
# Grace week queue management for the admin portal.
#
class Api::V1::Admin::GraceWeekRequestsController < Api::V1::Admin::BaseController

  before_action :set_grace_week, only: [:show, :approve, :deny]

  # GET /api/v1/admin/grace_week_requests
  def index
    scope = GraceWeekRequest.includes(plan: :user).order(created_at: :desc)
    scope = scope.where(status: params[:status]) if params[:status].present?

    paged = paginate(scope)

    render_success(
      data: paged.map { |g| grace_row(g) },
      meta: pagination_meta(paged)
    )
  end

  # GET /api/v1/admin/grace_week_requests/:id
  def show
    render_success(data: grace_detail(@grace))
  end

  # POST /api/v1/admin/grace_week_requests/:id/approve
  def approve
    GraceWeekService.approve!(grace: @grace, admin_note: params[:admin_note])
    render_success(message: "Grace week approved. Two half-payments scheduled.")
  rescue GraceWeekService::Error => e
    render_error(message: e.message)
  end

  # POST /api/v1/admin/grace_week_requests/:id/deny
  def deny
    GraceWeekService.deny!(grace: @grace, admin_note: params[:admin_note])
    render_success(message: "Grace week denied.")
  rescue GraceWeekService::Error => e
    render_error(message: e.message)
  end

  private

  def set_grace_week
    @grace = GraceWeekRequest.includes(plan: :user).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error(message: "Grace week request not found.", status: :not_found)
  end

  def grace_row(g)
    {
      id:           g.id,
      status:       g.status,
      reason:       g.reason,
      admin_note:   g.admin_note,
      halves_paid:  g.halves_paid,
      plan_id:      g.plan_id,
      plan_name:    g.plan&.name,
      client_name:  g.plan&.user&.full_name,
      client_email: g.plan&.user&.email,
      created_at:   g.created_at
    }
  end

  def grace_detail(g)
    grace_row(g).merge(
      plan: {
        id:              g.plan&.id,
        name:            g.plan&.name,
        monthly_payment: g.plan&.monthly_payment.to_f,
        next_payment_at: g.plan&.next_payment_at,
        status:          g.plan&.status
      }
    )
  end
end
