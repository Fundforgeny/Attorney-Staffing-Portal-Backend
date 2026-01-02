# frozen_string_literal: true

# This controller handles a user's email confirmation flow.
# It also immediately provides a password reset token to allow the user
# to set their password upon first login
class Users::ConfirmationsController < Users::BaseDeviseController
  # Handles GET confirmation?confirmation_token=abcdef
  def show
    # Use ActsAsTenant.without_tenant to perform a global search for the unique token.
    self.resource = ActsAsTenant.without_tenant do
      resource_class.confirm_by_token(params[:confirmation_token])
    end

    if resource.errors.empty?
      # The user's account is now confirmed. We generate a temporary
      # reset password token to allow them to set their password.
      raw_token, enc_token = Devise.token_generator.generate(User, :reset_password_token)
      resource.reset_password_token = enc_token
      resource.reset_password_sent_at = Time.current
      resource.save(validate: false)

      render json: {
        message: "Account confirmed successfully. Please set your password.",
        reset_password_token: raw_token
      }, status: :ok
    else
      # Use the standardized helper for a consistent error response.
      render_resource_errors(resource)
    end
  end

  # This action is for when the user submits a form to resend the confirmation email.
  # Handles POST confirmation/resend
  def create
    self.resource = resource_class.send_confirmation_instructions(email: params[:email])

    if successfully_sent?(resource)
      render json: { message: "Confirmation instructions have been re-sent." }, status: :ok
    else
      # Use the standardized helper for a consistent error response.
      render_resource_errors(resource)
    end
  end
end
