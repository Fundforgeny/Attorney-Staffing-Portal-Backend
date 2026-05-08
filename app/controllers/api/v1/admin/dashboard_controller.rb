# Api::V1::Admin::DashboardController
#
# GET /api/v1/admin/dashboard
# Returns live business-critical revenue, reserve, return, and plan-default data.
#
class Api::V1::Admin::DashboardController < Api::V1::Admin::BaseController

  def index
    render_success(data: {
      stats: stats,
      business_metrics: business_metrics,
      risk_metrics: risk_metrics_120_days,
      monthly_charts: monthly_charts,
      payment_status: payment_status_breakdown,
      plan_status: plan_status_breakdown,
      needs_new_card: needs_new_card_summary,
      grace_week: grace_week_summary,
      recent_payments: recent_payments_data
    })
  end

  private

  def stats
    current_revenue = revenue_for(current_30_range)
    prior_revenue = revenue_for(prior_30_range)

    {
      total_users: User.count,
      total_plans: Plan.count,
      active_plans: active_plans.count,
      overdue_plans: overdue_plans.count,
      default_rate_percent: percent(overdue_plans.count, active_plans.count),
      total_revenue: revenue_for(10.years.ago.beginning_of_day..Time.current.end_of_day),
      revenue_last_30_days: current_revenue,
      revenue_prior_30_days: prior_revenue,
      revenue_30_day_change_percent: percent_change(current_revenue, prior_revenue),
      needs_new_card: Payment.where(needs_new_card: true).count,
      pending_grace_weeks: GraceWeekRequest.where(status: :pending).count,
      leads: Plan.where.not(status: :paid).count
    }
  end

  def business_metrics
    current_revenue = revenue_for(current_30_range)
    prior_revenue = revenue_for(prior_30_range)
    risk = risk_metrics_120_days
    current_default_rate = percent(overdue_plans.count, active_plans.count)
    prior_default_rate = prior_30_day_default_rate_percent

    {
      current_30_day_revenue: current_revenue,
      prior_30_day_revenue: prior_revenue,
      revenue_30_day_change_percent: percent_change(current_revenue, prior_revenue),
      revenue_growth_direction: growth_direction(current_revenue, prior_revenue),
      estimated_reserve_needed_on_current_30_day_revenue: (current_revenue.to_d * risk[:return_amount_rate_percent].to_d / 100).to_f.round(2),
      reserve_rate_percent: risk[:return_amount_rate_percent],
      active_plans_count: active_plans.count,
      overdue_plans_count: overdue_plans.count,
      plan_default_rate_percent: current_default_rate,
      prior_30_day_default_rate_percent: prior_default_rate,
      default_rate_change_percent: percent_change(current_default_rate, prior_default_rate),
      default_trend_direction: current_default_rate > prior_default_rate ? "worse" : "better"
    }
  end

  def risk_metrics_120_days
    range = 120.days.ago.beginning_of_day..Time.current.end_of_day
    revenue_amount = revenue_for_decimal(range)

    voluntary_refunds_amount = Payment.where(refunded_at: range).sum(:refunded_amount).to_d
    alert_amount = amount_sum(Payment.where(created_at: range).where.not(chargeflow_alert_id: [nil, ""]))
    dispute_amount = amount_sum(Payment.where(created_at: range).where("disputed = ? OR chargeflow_dispute_id IS NOT NULL", true))
    returned_amount = voluntary_refunds_amount + alert_amount + dispute_amount

    current_30_return_amount = returned_amount_for(current_30_range)
    prior_30_return_amount = returned_amount_for(prior_30_range)
    current_30_revenue_amount = revenue_for_decimal(current_30_range)
    prior_30_revenue_amount = revenue_for_decimal(prior_30_range)
    current_30_return_rate = percent(current_30_return_amount, current_30_revenue_amount)
    prior_30_return_rate = percent(prior_30_return_amount, prior_30_revenue_amount)

    {
      window_days: 120,
      revenue_amount: revenue_amount.to_f.round(2),
      returned_amount: returned_amount.to_f.round(2),
      return_amount_rate_percent: percent(returned_amount, revenue_amount),
      estimated_return_per_10000_collected: (10_000.to_d * percent(returned_amount, revenue_amount).to_d / 100).to_f.round(2),
      voluntary_refunds_amount: voluntary_refunds_amount.to_f.round(2),
      alerts_count: Payment.where(created_at: range).where.not(chargeflow_alert_id: [nil, ""]).count,
      alerts_amount: alert_amount.to_f.round(2),
      disputes_count: Payment.where(created_at: range).where("disputed = ? OR chargeflow_dispute_id IS NOT NULL", true).count,
      disputes_amount: dispute_amount.to_f.round(2),
      current_30_day_return_amount: current_30_return_amount.to_f.round(2),
      current_30_day_return_rate_percent: current_30_return_rate,
      prior_30_day_return_amount: prior_30_return_amount.to_f.round(2),
      prior_30_day_return_rate_percent: prior_30_return_rate,
      return_rate_30_day_change_percent: percent_change(current_30_return_rate, prior_30_return_rate),
      return_trend_direction: current_30_return_rate > prior_30_return_rate ? "worse" : "better"
    }
  end

  def returned_amount_for(range)
    voluntary_refunds_amount = Payment.where(refunded_at: range).sum(:refunded_amount).to_d
    alert_amount = amount_sum(Payment.where(created_at: range).where.not(chargeflow_alert_id: [nil, ""]))
    dispute_amount = amount_sum(Payment.where(created_at: range).where("disputed = ? OR chargeflow_dispute_id IS NOT NULL", true))
    voluntary_refunds_amount + alert_amount + dispute_amount
  end

  def current_30_range
    30.days.ago.beginning_of_day..Time.current.end_of_day
  end

  def prior_30_range
    60.days.ago.beginning_of_day..30.days.ago.end_of_day
  end

  def active_plans
    Plan.where(status: :paid)
  end

  def overdue_plans
    active_plans.where("next_payment_at < ?", Time.current)
  end

  def succeeded_payments
    Payment.where(status: :succeeded)
  end

  def revenue_for(range)
    revenue_for_decimal(range).to_f.round(2)
  end

  def revenue_for_decimal(range)
    amount_sum(succeeded_payments.where(created_at: range))
  end

  def amount_sum(scope)
    amount = scope.sum(:total_payment_including_fee).to_d
    amount = scope.sum(:payment_amount).to_d if amount.zero?
    amount
  end

  def prior_30_day_default_rate_percent
    cutoff = 30.days.ago.end_of_day
    paid_plans_prior = Plan.where(status: :paid).where("created_at <= ?", cutoff)
    overdue_prior = paid_plans_prior.where("next_payment_at < ?", cutoff)
    percent(overdue_prior.count, paid_plans_prior.count)
  end

  def percent(numerator, denominator)
    denominator = denominator.to_d
    return 0.0 if denominator.zero?

    ((numerator.to_d / denominator) * 100).to_f.round(2)
  end

  def percent_change(current, previous)
    previous = previous.to_d
    return 0.0 if previous.zero?

    (((current.to_d - previous) / previous) * 100).to_f.round(2)
  end

  def growth_direction(current, previous)
    current.to_d >= previous.to_d ? "up" : "down"
  end

  def monthly_charts
    months = 6.downto(0).map { |i| i.months.ago.beginning_of_month }
    labels = months.map { |m| m.strftime("%b %Y") }

    monthly_revenue = months.map { |m| revenue_for(m..m.end_of_month) }
    monthly_return_amount = months.map { |m| returned_amount_for(m..m.end_of_month).to_f.round(2) }
    monthly_return_rate = months.each_with_index.map { |_m, index| percent(monthly_return_amount[index], monthly_revenue[index]) }
    monthly_active_plans = months.map { |m| Plan.where(status: :paid).where("created_at <= ?", m.end_of_month).count }
    monthly_overdue_plans = months.map { |m| Plan.where(status: :paid).where("created_at <= ?", m.end_of_month).where("next_payment_at < ?", m.end_of_month).count }
    monthly_default_rate = months.each_with_index.map { |_m, index| percent(monthly_overdue_plans[index], monthly_active_plans[index]) }

    {
      labels: labels,
      monthly_revenue: monthly_revenue,
      monthly_return_amount: monthly_return_amount,
      monthly_return_rate_percent: monthly_return_rate,
      monthly_active_plans: monthly_active_plans,
      monthly_overdue_plans: monthly_overdue_plans,
      monthly_default_rate_percent: monthly_default_rate
    }
  end

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
    plans_needing_card = Plan.joins(:payments)
                             .where(payments: { needs_new_card: true })
                             .distinct
                             .limit(5)
                             .includes(:user)

    plans_needing_card.map do |plan|
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
    Payment.includes(plan: :user, payment_method: [])
           .order(created_at: :desc)
           .limit(10)
           .map { |payment| payment_row(payment) }
  end

  def payment_row(payment)
    {
      id: payment.id,
      plan_id: payment.plan_id,
      plan_name: payment.plan&.name,
      client_name: payment.plan&.user&.full_name,
      client_email: payment.plan&.user&.email,
      amount: payment.payment_amount.to_f,
      total_amount: payment.total_payment_including_fee.to_f,
      status: payment.status,
      payment_type: payment.payment_type,
      charge_id: payment.charge_id,
      refund_transaction_id: payment.refund_transaction_id,
      refundable_amount: payment.refundable_amount.to_f,
      refunded_amount: payment.refunded_amount.to_f,
      disputed: payment.disputed?,
      chargeflow_alert_id: payment.chargeflow_alert_id,
      chargeflow_dispute_id: payment.chargeflow_dispute_id,
      disputed_at: payment.disputed_at,
      paid_at: payment.paid_at,
      scheduled_at: payment.scheduled_at,
      created_at: payment.created_at,
      card_brand: payment.payment_method&.card_brand,
      card_last4: payment.payment_method&.last4
    }
  end
end
