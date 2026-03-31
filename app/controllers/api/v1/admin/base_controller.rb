# Api::V1::Admin::BaseController
#
# Base controller for all admin API endpoints.
# Uses a signed JWT token issued at /api/v1/admin/auth/sign_in.
#
class Api::V1::Admin::BaseController < ActionController::API
  include ApiResponse

  before_action :authenticate_admin!

  private

  def authenticate_admin!
    token = request.headers["Authorization"]&.split(" ")&.last
    return render_error(message: "Unauthorized", status: :unauthorized) if token.blank?

    payload = Warden::JWTAuth::TokenDecoder.new.call(token)
    # Admin tokens carry sub = "admin:<id>"
    sub = payload["sub"].to_s
    unless sub.start_with?("admin:")
      return render_error(message: "Unauthorized", status: :unauthorized)
    end

    admin_id = sub.split(":").last.to_i
    @current_admin = AdminUser.find_by(id: admin_id)
    render_error(message: "Unauthorized", status: :unauthorized) unless @current_admin
  rescue JWT::DecodeError, Warden::JWTAuth::Errors::RevokedToken, StandardError
    render_error(message: "Unauthorized", status: :unauthorized)
  end

  def current_admin
    @current_admin
  end

  # Pagination helpers
  def page
    (params[:page] || 1).to_i
  end

  def per_page
    [(params[:per_page] || 25).to_i, 100].min
  end

  def paginate(scope)
    scope.page(page).per(per_page)
  end

  def pagination_meta(scope)
    {
      current_page:  scope.current_page,
      total_pages:   scope.total_pages,
      total_count:   scope.total_count,
      per_page:      scope.limit_value
    }
  end
end
