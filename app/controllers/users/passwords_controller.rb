class Users::PasswordsController < Users::BaseDeviseController
  # POST /password
  # This method handles the initial "forgot password" request. It finds the user
  # by email and sends them a password reset email.
  def create
    self.resource = ActsAsTenant.without_tenant do
      resource_class.send_reset_password_instructions(resource_params)
    end

    if successfully_sent?(resource)
      render json: { message: "If your email is in our system, you will receive a password reset link." }, status: :ok
    else
      render_resource_errors(resource)
    end
  end

  # PUT /password
  # This method handles the password reset using the token from the email.
  def update
    self.resource = ActsAsTenant.without_tenant do
      resource_class.reset_password_by_token(resource_params)
    end

    # Devise's `reset_password_by_token` automatically validates the new password.
    if resource.errors.empty?
      # The user has successfully reset their password.
      resource.unlock_access! if unlockable?(resource)

      render json: { message: "Your password has been changed successfully. You can now log in." }, status: :ok
    else
      # Use the standardized helper for a consistent error response.
      render_resource_errors(resource)
    end
  end

  protected

  private

  def unlockable?(resource)
    resource.respond_to?(:unlock_access!) &&
      resource.respond_to?(:unlock_strategy_enabled?) &&
      resource.unlock_strategy_enabled?(:email)
  end

  def resource_params
    params.require(:user).permit(:email, :reset_password_token, :password, :password_confirmation)
  end
end
