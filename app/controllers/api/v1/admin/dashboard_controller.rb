# Api::V1::Admin::DashboardController
#
# GET /api/v1/admin/dashboard
# Returns all stats and chart data for the admin dashboard.
#
class Api::V1::Admin::DashboardController < Api::V1::Admin::BaseController

  def index
    render_success(data: {
      stats:          stats,
      monthly_charts: monthly_charts,
      payment_status: payment_status_breakdown,
      plan_status:    plan_status_breakdown,
      needs_new_card: needs_new_card_summary,
      grace_week:     grace_week_summary,
      recent_payments: recent_payments_data
    })
  end

  private

  def stats
    {
      total_users:         User.count,
      total_plans:         Plan.count,
      active_plans:        Plan.where(status: :paid).count,
      total_revenue:       Payment.where(status: :succeeded).sum(:payment_amount).to_f.round(2),
      total_payments:      Payment.count,
      succeeded_payments:  Payment.where(status: :succeeded).count,
      failed_payments:     Payment.where(status: :failed).count,
      needs_new_card:      Payment.where(needs_new_card: true).count,
      pending_grace_weeks: GraceWeekRequest.where(status: :pending).count,
      leads:               Plan.where.not(status: :paid).count
    }
  end

  def monthly_charts
    months = 6.downto(0).map { |i| i.months.ago.beginning_of_month }
    labels = months.map { |m| m.strftime("%b %Y") }

    monthly_revenue = months.map do |m|
      Payment.where(status: :succeeded)
             .where(created_at: m..m.end_of_month)
             .sum(:payment_amount).to_f.round(2)
    end

    monthly_success_payments = months.map do |m|
      Payment.where(status: :succeeded)
             .where(created_at: m..m.end_of_month)
             .count
    end

    monthly_new_plans = months.map do |m|
      Plan.where(status: :paid)
          .where(created_at: m..m.end_of_month)
          .count
    end

    monthly_failed_payments = months.map do |m|
      Payment.where(status: :failed)
             .where(created_at: m..m.end_of_month)
             .count
    end

    {
      labels:                   labels,
      monthly_revenue:          monthly_revenue,
      monthly_success_payments: monthly_success_payments,
      monthly_new_plans:        monthly_new_plans,
      monthly_failed_payments:  monthly_failed_payments
    }
  end

  def payment_status_breakdown
    {
      succeeded: Payment.where(status: :succeeded).count,
      pending:   Payment.where(status: [:pending, :processing]).count,
      failed:    Payment.where(status: :failed).count,
      cancelled: 0  # no cancelled status in Payment enum
    }
  end

  def plan_status_breakdown
    {
      paid:    Plan.where(status: :paid).count,
      draft:   Plan.where(status: :draft).count,
      failed:  Plan.where(status: :failed).count
    }
  end

  def needs_new_card_summary
    plans_needing_card = Plan.joins(:payments)
                             .where(payments: { needs_new_card: true })
                             .distinct
                             .limit(5)
                             .includes(:user)

    plans_needing_card.map do |plan|
      {
        plan_id:     plan.id,
        plan_name:   plan.name,
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
        id:          gw.id,
        plan_id:     gw.plan_id,
        client_name: gw.plan&.user&.full_name,
        reason:      gw.reason,
        created_at:  gw.created_at
      }
    end
  end

  def recent_payments_data
    Payment.includes(plan: :user)
           .order(created_at: :desc)
           .limit(10)
           .map do |p|
      {
        id:           p.id,
        plan_id:      p.plan_id,
        client_name:  p.plan&.user&.full_name,
        amount:       p.payment_amount.to_f,
        status:       p.status,
        payment_type: p.payment_type,
        created_at:   p.created_at
      }
    end
  end
end
