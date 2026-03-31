# Api::V1::Admin::LeadsController
#
# Leads = all non-paid plans (draft, failed, etc.)
#
class Api::V1::Admin::LeadsController < Api::V1::Admin::BaseController

  # GET /api/v1/admin/leads
  def index
    scope = Plan.includes(:user)
                .where.not(status: Plan.statuses[:paid])
                .order(created_at: :desc)

    scope = scope.where(status: params[:status]) if params[:status].present?
    if params[:q].present?
      scope = scope.joins(:user)
                   .where("users.email ILIKE ? OR users.first_name ILIKE ? OR users.last_name ILIKE ? OR plans.name ILIKE ?",
                          "%#{params[:q]}%", "%#{params[:q]}%", "%#{params[:q]}%", "%#{params[:q]}%")
    end

    paged = paginate(scope)

    render_success(
      data: paged.map { |p| lead_row(p) },
      meta: pagination_meta(paged)
    )
  end

  private

  def lead_row(plan)
    {
      id:            plan.id,
      plan_name:     plan.name,
      status:        plan.status,
      client_name:   plan.user&.full_name,
      client_email:  plan.user&.email,
      total_payment: plan.total_payment.to_f,
      duration:      plan.duration,
      created_at:    plan.created_at
    }
  end
end
