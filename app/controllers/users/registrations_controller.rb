# This controller inherits from the custom base class to get common API
# functionality like JSON rendering, error handling, and multi-tenancy setup.
class Users::RegistrationsController < Users::BaseDeviseController
  # Ensures a user is logged in to access account management actions
  before_action :authenticate_user!, only: [ :update, :update_personal_info, :change_email, :change_password ]

  # PATCH /resource
  # This is the single, unified method for a user to update all their non-sensitive
  # account information, including their email address and their schedule.
  def update
    # Use the Devise current_user helper to get the authenticated user object.
    self.resource = current_user

    # Use `update_without_password`. Devise helper, designed to bypass password validations
    if resource.update_without_password(user_params)
      # Return the updated resource using the blueprint
      render json: UserBlueprint.render(resource, view: :full_view), status: :ok
    else
      render_resource_errors(resource)
    end
  end

  # PATCH /resource/update_personal_info
  # This method updates a user's general information, but NOT their email or password.
  def update_personal_info
    self.resource = current_user

    # Use `update_without_password` to handle updates that do not include the password.
    if resource.update_without_password(personal_info_params)
      # Return the updated resource using the blueprint
      render json: UserBlueprint.render(resource, view: :full_view), status: :ok
    else
      render_resource_errors(resource)
    end
  end

  # PATCH /resource/change_email
  def change_email
    self.resource = current_user

    # Use Devise's `update_with_password` helper. This method securely validates
    # the current password and performs the email change.
    if resource.update_with_password(email_params)
      # Return the updated resource using the blueprint
      render json: { message: "User email updated successfully." }, status: :ok
    else
      render_resource_errors(resource)
    end
  end

  # PATCH /resource/change_password
  def change_password
    self.resource = current_user

    # Use Devise's `update_with_password` helper. This method securely validates
    # the old password and updates the password if it's correct.
    if resource.update_with_password(password_params)
      # In a JWT API, the client handles the token, so bypass_sign_in is not needed.
      render json: { message: "Password updated successfully." }, status: :ok
    else
      render_resource_errors(resource)
    end
  end

  protected

  # Permits all non-sensitive parameters, including the email,
  # and nested attributes for user availabilities.
  def user_params
    params.require(:user).permit(
      :email,
      :first_name,
      :last_name,
      :phone,
      :dob,
      :address_street,
      :city,
      :state,
      :country,
      :annual_salary,
      :contact_source,
    )
  end

  # Permits parameters for general account information (without email or password),
  # including nested attributes for user availabilities.
  def personal_info_params
    params.require(:user).permit(
      :first_name,
      :last_name,
      :phone,
      :dob,
      :address_street,
      :city,
      :state,
      :country,
      :annual_salary,
      :contact_source,
    )
  end

  # Permits parameters for changing the email.
  # Requires the `current_password` for security.
  def email_params
    params.require(:user).permit(:email, :current_password)
  end

  # Permits parameters for changing the password.
  def password_params
    params.require(:user).permit(:password, :password_confirmation, :current_password)
  end
end
