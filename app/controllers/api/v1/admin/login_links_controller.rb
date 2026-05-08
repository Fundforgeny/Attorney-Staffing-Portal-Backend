class Api::V1::Admin::LoginLinksController < ActionController::API
  include ApiResponse

  def create
    email = params[:email].to_s.strip.downcase
    return render_error(message: "Email is required", status: :bad_request) if email.blank?

    admin = AdminUserBootstrapService.find_or_bootstrap!(email)
    login_link = AdminLoginLinkService.new(admin: admin).generate_link

    GhlWebhookService.send_admin_login_magic_link!(admin: admin, login_magic_link: login_link)

    render_success(
      data: { email: admin.email },
      message: "If your email is authorized, a login link has been sent.",
      status: :ok
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[AdminLoginLinks] Could not bootstrap admin: #{e.record.errors.full_messages.join(', ')}")
    render_success(message: "If your email is authorized, a login link has been sent.", status: :ok)
  rescue ActiveRecord::RecordNotFound
    render_success(message: "If your email is authorized, a login link has been sent.", status: :ok)
  rescue StandardError => e
    Rails.logger.error("[AdminLoginLinks] Request failed: #{e.class}: #{e.message}")
    render_error(message: "Unable to send login link", status: :unprocessable_entity)
  end

  def show
    admin = AdminLoginLinkService.verify!(params[:token])
    token = AdminAuthTokenService.generate(admin)

    render_success(
      data: {
        token: token,
        admin_id: admin.id,
        email: admin.email,
        first_name: admin.first_name,
        last_name: admin.last_name
      },
      message: "Login link verified successfully",
      status: :ok
    )
  rescue AdminLoginLinkService::InvalidTokenError,
         AdminLoginLinkService::ExpiredTokenError,
         AdminLoginLinkService::UsedTokenError => e
    render_error(message: e.message, status: :unprocessable_entity)
  rescue StandardError => e
    Rails.logger.error("[AdminLoginLinks] Verification failed: #{e.class}: #{e.message}")
    render_error(message: "Unable to verify login link", status: :unprocessable_entity)
  end
end
