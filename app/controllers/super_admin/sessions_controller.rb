module SuperAdmin
  class SessionsController < ApplicationController
    def new
    end

    def create
      email = params.dig(:user, :email).to_s.downcase.strip
      password = params.dig(:user, :password).to_s

      user = User.find_by(email: email)

      if user&.super_admin? && user.valid_password?(password)
        sign_in(:user, user)
        redirect_to active_admin_root_path
      else
        flash.now[:alert] = "Invalid email or password."
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      sign_out(:user)
      redirect_to super_admin_sign_in_path
    end
  end
end
