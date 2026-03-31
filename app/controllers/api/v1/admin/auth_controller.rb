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

    token = generate_admin_token(admin)

    render_success(data: {
      token:      token,
      admin_id:   admin.id,
      email:      admin.email,
      first_name: admin.first_name,
      last_name:  admin.last_name
    })
  end

  private

  def generate_admin_token(admin)
    # Build a JWT with sub = "admin:<id>" so BaseController can distinguish admin tokens
    secret = ENV["DEVISE_JWT_SECRET_KEY"].presence ||
             Rails.application.credentials.devise_jwt_secret_key.presence ||
             Rails.application.secret_key_base

    payload = {
      sub: "admin:#{admin.id}",
      iat: Time.current.to_i,
      exp: 8.hours.from_now.to_i,
      jti: SecureRandom.uuid
    }

    JWT.encode(payload, secret, "HS256")
  end
end
