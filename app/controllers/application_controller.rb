class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_super_admin_user

  def authenticate_super_admin_user!
    unless user_signed_in?
      redirect_to super_admin_sign_in_path
      return
    end

    return if current_user&.super_admin?

    sign_out(:user)
    redirect_to super_admin_sign_in_path
  end

  def current_super_admin_user
    current_user if current_user&.super_admin?
  end
end
