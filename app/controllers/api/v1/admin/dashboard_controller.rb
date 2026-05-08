class Api::V1::Admin::DashboardController < Api::V1::Admin::BaseController
  def index
    render_success(data: AdminDashboardMetricsService.new.call.merge(
      payment_status: payment_status_breakdown,
      plan_status: plan_status_breakdown,
      needs_new_card: needs_new_card_summary,
      grace_week: grace_week_summary,
      recent_payments: recent_payments_data
    ))
  end

  private

  def payment_status_breakdown
    {
      succeeded: Payment.where(status: :succeeded).count,
      pending: Payment.where(status: [:pending, :processing]).count,
      failed: Payment.where(status: :failed).count,
      cancelled: 0
    }
  end

  def plan_status_breakdown
    {
      paid: Plan.where(status: :paid).count,
      draft: Plan.where(status: :draft).count,
      failed: Plan.where(status: :failed).count
    }
  end

  def needs_new_card_summary
    Plan.joins(:payments)
        .where(payments: { needs_new_card: true })
        .distinct
        .limit(5)
        .includes(:user)
        .map do |plan|
      {
        plan_id: plan.id,
        plan_name: plan.name,
        client_name: plan.user&.full_name,
        client_email: plan.user&.email
      }
    end
  end

  def grace_week_summary
    GraceWeekRequest.where(status: :pending)
                    .includes(plan: :user)
                    .order(created_at: :desc)
                    .limit(5)
                    .map do |gw|
      {
        id: gw.id,
        plan_id: gw.plan_id,
        client_name: gw.plan&.user&.full_name,
        reason: gw.reason,
        created_at: gw.created_at
      }
    end
  end

  def recent_payments_data
    Payment.includes(plan: :user)
           .order(created_at: :desc)
           .limit(10)
           .map do |p|
      {
        id: p.id,
        plan_id: p.plan_id,
        client_name: p.plan&.user&.full_name,
        amount: p.payment_amount.to_f,
        total_amount: p.total_payment_including_fee.to_f,
        status: p.status,
        payment_type: p.payment_type,
        charge_id: p.charge_id,
        created_at: p.created_at
      }
    end
  end
end
