# Api::V1::Admin::UsersController
#
# User management for the admin portal.
#
class Api::V1::Admin::UsersController < Api::V1::Admin::BaseController

  before_action :set_user, only: [:show]

  # GET /api/v1/admin/users
  def index
    scope = User.includes(:plans, :payment_methods, :firm).order(created_at: :desc)

    scope = scope.where(user_type: params[:user_type]) if params[:user_type].present?
    if params[:q].present?
      scope = scope.where("email ILIKE ? OR first_name ILIKE ? OR last_name ILIKE ?",
                          "%#{params[:q]}%", "%#{params[:q]}%", "%#{params[:q]}%")
    end

    paged = paginate(scope)

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

  def set_user
    @user = User.includes(:plans, :payment_methods, :firm).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error(message: "User not found.", status: :not_found)
  end

  def user_row(u)
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
          monthly_payment: p.monthly_payment.to_f,
          next_payment_at: p.next_payment_at,
          created_at:      p.created_at
        }
      end,
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
end
