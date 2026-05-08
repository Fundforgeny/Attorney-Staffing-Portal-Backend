# Api::V1::Admin::UsersController
#
# User management and client/payment search for the admin portal.
#
class Api::V1::Admin::UsersController < Api::V1::Admin::BaseController

  before_action :set_user, only: [:show]

  # GET /api/v1/admin/users
  def index
    scope = User.includes(:plans, :payment_methods, :firm).order(created_at: :desc)

    scope = scope.where(user_type: params[:user_type]) if params[:user_type].present?
    scope = apply_search(scope, params[:q]) if params[:q].present?

    paged = paginate(scope.distinct)

    render_success(
      data: paged.map { |u| user_row(u) },
      meta: pagination_meta(paged)
    )
  end

  # GET /api/v1/admin/users/:id
  def show
    render_success(data: user_detail(@user))
  end

  private

  def apply_search(scope, raw_query)
    query = raw_query.to_s.strip
    return scope if query.blank?

    normalized_phone = query.gsub(/\D/, "")
    amount = parse_amount(query)
    date = parse_date(query)

    scope = scope.left_joins(plans: :payments).left_joins(:payment_methods)

    conditions = []
    values = []

    like_query = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    conditions << "users.email ILIKE ?"
    values << like_query
    conditions << "users.first_name ILIKE ?"
    values << like_query
    conditions << "users.last_name ILIKE ?"
    values << like_query
    conditions << "CONCAT_WS(' ', users.first_name, users.last_name) ILIKE ?"
    values << like_query
    conditions << "users.phone ILIKE ?"
    values << like_query
    conditions << "plans.name ILIKE ?"
    values << like_query
    conditions << "plans.checkout_session_id ILIKE ?"
    values << like_query
    conditions << "payments.charge_id ILIKE ?"
    values << like_query
    conditions << "payments.refund_transaction_id ILIKE ?"
    values << like_query
    conditions << "payments.decline_reason ILIKE ?"
    values << like_query
    conditions << "payment_methods.last4 ILIKE ?"
    values << like_query
    conditions << "payment_methods.card_brand ILIKE ?"
    values << like_query

    if normalized_phone.present?
      phone_query = "%#{normalized_phone}%"
      conditions << "REGEXP_REPLACE(COALESCE(users.phone, ''), '[^0-9]', '', 'g') ILIKE ?"
      values << phone_query
      conditions << "payment_methods.last4 ILIKE ?" if normalized_phone.length >= 4
      values << "%#{normalized_phone[-4, 4]}%" if normalized_phone.length >= 4
    end

    if amount
      conditions << "payments.payment_amount = ?"
      values << amount
      conditions << "payments.total_payment_including_fee = ?"
      values << amount
      conditions << "payments.refunded_amount = ?"
      values << amount
      conditions << "plans.total_payment = ?"
      values << amount
      conditions << "plans.monthly_payment = ?"
      values << amount
      conditions << "plans.down_payment = ?"
      values << amount
    end

    if date
      conditions << "DATE(payments.scheduled_at) = ?"
      values << date
      conditions << "DATE(payments.paid_at) = ?"
      values << date
      conditions << "DATE(payments.created_at) = ?"
      values << date
      conditions << "DATE(plans.created_at) = ?"
      values << date
      conditions << "DATE(users.created_at) = ?"
      values << date
    end

    scope.where(conditions.join(" OR "), *values)
  end

  def parse_amount(value)
    cleaned = value.to_s.gsub(/[$,]/, "").strip
    return nil unless cleaned.match?(/\A\d+(\.\d{1,2})?\z/)

    BigDecimal(cleaned)
  rescue ArgumentError
    nil
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def set_user
    @user = User.includes(:firm, :payment_methods, plans: :payments).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error(message: "User not found.", status: :not_found)
  end

  def user_row(u)
    latest_payment = Payment.joins(:plan)
                            .where(plans: { user_id: u.id })
                            .order(created_at: :desc)
                            .first

    {
      id:         u.id,
      email:      u.email,
      first_name: u.first_name,
      last_name:  u.last_name,
      full_name:  u.full_name,
      user_type:  u.user_type,
      phone:      u.phone,
      firm_name:  u.firm&.name,
      plan_count: u.plans.size,
      payment_count: u.plans.sum { |plan| plan.payments.size },
      latest_payment_amount: latest_payment&.total_payment_including_fee&.to_f || latest_payment&.payment_amount&.to_f,
      latest_payment_status: latest_payment&.status,
      latest_payment_at: latest_payment&.paid_at || latest_payment&.scheduled_at || latest_payment&.created_at,
      latest_transaction_id: latest_payment&.charge_id,
      created_at: u.created_at
    }
  end

  def user_detail(u)
    user_row(u).merge(
      plans: u.plans.order(created_at: :desc).map do |p|
        {
          id:              p.id,
          name:            p.name,
          status:          p.status,
          total_payment:   p.total_payment.to_f,
          total_payment_plan_amount: p.total_payment_plan_amount.to_f,
          remaining_balance: p.remaining_balance_logic.to_f,
          monthly_payment: p.monthly_payment.to_f,
          down_payment:    p.down_payment.to_f,
          duration:        p.duration,
          checkout_session_id: p.checkout_session_id,
          next_payment_at: p.next_payment_at,
          created_at:      p.created_at,
          payments: p.payments.order(created_at: :desc).map { |payment| payment_row(payment) }
        }
      end,
      payments: u.plans.flat_map { |plan| plan.payments.map { |payment| payment_row(payment, plan) } }
                 .sort_by { |payment| payment[:created_at] || Time.at(0) }
                 .reverse,
      payment_methods: u.payment_methods.ordered_for_user.map do |pm|
        {
          id:         pm.id,
          card_brand: pm.card_brand,
          last4:      pm.last4,
          exp_month:  pm.exp_month,
          exp_year:   pm.exp_year,
          is_default: pm.is_default?
        }
      end
    )
  end

  def payment_row(payment, plan = nil)
    plan ||= payment.plan

    {
      id: payment.id,
      plan_id: payment.plan_id,
      plan_name: plan&.name,
      payment_type: payment.payment_type,
      status: payment.status,
      amount: payment.payment_amount.to_f,
      total_amount: payment.total_payment_including_fee.to_f,
      transaction_fee: payment.transaction_fee.to_f,
      refundable_amount: payment.refundable_amount.to_f,
      refunded_amount: payment.refunded_amount.to_f,
      charge_id: payment.charge_id,
      refund_transaction_id: payment.refund_transaction_id,
      refunded_at: payment.refunded_at,
      last_refund_reason: payment.last_refund_reason,
      scheduled_at: payment.scheduled_at,
      paid_at: payment.paid_at,
      created_at: payment.created_at,
      card_brand: payment.payment_method&.card_brand,
      card_last4: payment.payment_method&.last4,
      retry_count: payment.retry_count || 0,
      next_retry_at: payment.next_retry_at,
      decline_reason: payment.decline_reason,
      needs_new_card: payment.needs_new_card?
    }
  end
end
