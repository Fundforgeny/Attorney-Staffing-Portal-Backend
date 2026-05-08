# Api::V1::Admin::AdminUsersController
#
# Admin-user management for the React admin portal.
# Only fund_forge_admin users can create or update admin users.
#
class Api::V1::Admin::AdminUsersController < Api::V1::Admin::BaseController
  before_action :require_full_access!
  before_action :set_admin_user, only: [:show, :update]

  # GET /api/v1/admin/admin_users
  def index
    scope = AdminUser.order(created_at: :desc)

    if params[:q].present?
      scope = scope.where(
        "email ILIKE ? OR first_name ILIKE ? OR last_name ILIKE ?",
        "%#{params[:q]}%", "%#{params[:q]}%", "%#{params[:q]}%"
      )
    end

    scope = scope.where(role: params[:role]) if params[:role].present?

    paged = paginate(scope)

    render_success(
      data: paged.map { |admin_user| admin_user_row(admin_user) },
      meta: pagination_meta(paged)
    )
  end

  # GET /api/v1/admin/admin_users/:id
  def show
    render_success(data: admin_user_row(@admin_user))
  end

  # POST /api/v1/admin/admin_users
  def create
    admin_user = AdminUser.new(admin_user_params)

    if admin_user.save
      render_success(data: admin_user_row(admin_user), message: "Admin user created successfully.", status: :created)
    else
      render_error(errors: admin_user.errors.full_messages, message: "Admin user could not be created.")
    end
  end

  # PATCH/PUT /api/v1/admin/admin_users/:id
  def update
    clean_params = admin_user_params
    if clean_params[:password].blank?
      clean_params.delete(:password)
      clean_params.delete(:password_confirmation)
    end

    if @admin_user.update(clean_params)
      render_success(data: admin_user_row(@admin_user), message: "Admin user updated successfully.")
    else
      render_error(errors: @admin_user.errors.full_messages, message: "Admin user could not be updated.")
    end
  end

  private

  def require_full_access!
    render_error(message: "Only Fund Forge admins can manage admin users.", status: :forbidden) unless current_admin&.full_access?
  end

  def set_admin_user
    @admin_user = AdminUser.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error(message: "Admin user not found.", status: :not_found)
  end

  def admin_user_params
    params.require(:admin_user).permit(
      :email,
      :first_name,
      :last_name,
      :contact_number,
      :role,
      :password,
      :password_confirmation
    )
  end

  def admin_user_row(admin_user)
    {
      id: admin_user.id,
      email: admin_user.email,
      first_name: admin_user.first_name,
      last_name: admin_user.last_name,
      full_name: "#{admin_user.first_name} #{admin_user.last_name}".strip,
      contact_number: admin_user.contact_number,
      role: admin_user.role,
      can_refund_payments: admin_user.can_refund_payments?,
      full_access: admin_user.full_access?,
      created_at: admin_user.created_at,
      updated_at: admin_user.updated_at
    }
  end
end
