# Api::V1::Admin::AuthController
#
# Issues a JWT token for AdminUser credentials.
# POST /api/v1/admin/auth/sign_in  { email, password }
#
class Api::V1::Admin::AuthController < ActionController::API
  include ApiResponse

  # POST /api/v1/admin/auth/sign_in
  def sign_in
    admin = AdminUser.find_by(email: params[:email]&.downcase&.strip)

    unless admin&.valid_password?(params[:password])
      return render_error(message: "Invalid email or password", status: :unauthorized)
    end

    token = AdminAuthTokenService.generate(admin)

    render_success(data: {
      token:      token,
      admin_id:   admin.id,
      email:      admin.email,
      first_name: admin.first_name,
      last_name:  admin.last_name
    })
  end

end
