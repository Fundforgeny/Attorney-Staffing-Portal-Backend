class HomeController < ApplicationController
  def index
    if user_signed_in? && current_user&.super_admin?
      redirect_to active_admin_root_path
    else
      redirect_to super_admin_sign_in_path
    end
  end
end
