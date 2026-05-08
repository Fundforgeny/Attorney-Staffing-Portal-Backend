# Api::V1::Admin::DashboardController
#
# GET /api/v1/admin/dashboard
# Returns live stats and payment-risk data for the admin dashboard.
#
class Api::V1::Admin::DashboardController < Api::V1::Admin::BaseController

  def index
    render_success(data: {
      stats:          stats,
      risk_metrics:   risk_metrics_120_days,
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

  def risk_metrics_120_days
    range = 120.days.ago.beginning_of_day..Time.current.end_of_day
    payments = Payment.where(created_at: range)
    successful_payments = payments.where(status: :succeeded)
    alerts = payments.where.not(chargeflow_alert_id: [nil, ""])
    disputes = payments.where("disputed = ? OR chargeflow_dispute_id IS NOT NULL", true)
    returns = payments.where(status: :failed)

    total_success_count = successful_payments.count
    total_success_amount = successful_payments.sum(:total_payment_including_fee).to_d
    total_success_amount = successful_payments.sum(:payment_amount).to_d if total_success_amount.zero?

    dispute_count = disputes.count
    dispute_amount = disputes.sum(:total_payment_including_fee).to_d
    dispute_amount = disputes.sum(:payment_amount).to_d if dispute_amount.zero?

    return_count = returns.count
    return_amount = returns.sum(:total_payment_including_fee).to_d
    return_amount = returns.sum(:payment_amount).to_d if return_amount.zero?

    {
      window_days: 120,
      alerts_count: alerts.count,
      alerts_amount: decimal_to_fallback_amount(alerts),
      disputes_count: dispute_count,
      disputes_amount: dispute_amount.to_f.round(2),
      returned_payments_count: return_count,
      returned_payments_amount: return_amount.to_f.round(2),
      successful_payments_count: total_success_count,
      successful_payments_amount: total_success_amount.to_f.round(2),
      dispute_rate_percent: percent(dispute_count, total_success_count),
      dispute_amount_rate_percent: percent(dispute_amount, total_success_amount),
      return_rate_percent: percent(return_count, total_success_count),
      return_amount_rate_percent: percent(return_amount, total_success_amount)
    }
  end

  def decimal_to_fallback_amount(scope)
    amount = scope.sum(:total_payment_including_fee).to_d
    amount = scope.sum(:payment_amount).to_d if amount.zero?
    amount.to_f.round(2)
  end

  def percent(numerator, denominator)
    denominator = denominator.to_d
    return 0.0 if denominator.zero?

    ((numerator.to_d / denominator) * 100).to_f.round(2)
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
      cancelled: 0
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
