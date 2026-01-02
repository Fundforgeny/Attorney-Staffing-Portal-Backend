class Users::UnlocksController < Users::BaseDeviseController
  # GET /resource/unlock?unlock_token=abcdef
  def show
    self.resource = ActsAsTenant.without_tenant do
      resource_class.unlock_access_by_token(params[:unlock_token])
    end

    if resource.errors.empty?
      render json: { message: "Account unlocked successfully. You can now log in." }, status: :ok
    else
      # Use the standardized helper for a consistent error response.
      render_resource_errors(resource)
    end
  end

  # POST /resource/unlock
  def create
    self.resource = resource_class.send_unlock_instructions(email: params[:email])

    if successfully_sent?(resource)
      render json: { message: "Unlock instructions sent." }, status: :ok
    else
      # Use the standardized helper for a consistent error response.
      render_resource_errors(resource)
    end
  end
end
