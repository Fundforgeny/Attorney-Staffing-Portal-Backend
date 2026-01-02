# This controller handles user session management (login and logout) for API.
# It inherits from Devise's SessionsController to leverage its core authentication
# and session handling logic, while overriding key behaviors to be API-specific.
class Users::SessionsController < Devise::SessionsController
  before_action :force_json
  include SharedDeviseMethods

  # Overrides the default `create` action to provide a custom, API-friendly JSON response
  # for both successful and failed login attempts. This approach avoids Devise's
  # default HTML redirection behavior.
  def create
    # Authenticates user using Warden, the middleware Devise is built on.
    # The `warden.authenticate` method (without the bang `!`) returns the authenticated
    # user object on success and `nil` or `false` on failure, preventing
    # automatic redirects to the login page.
    self.resource = warden.authenticate(auth_options)

    # A conditional block to handle the two possible outcomes of the authentication attempt.
    if resource
      # --- Successful Login Path ---
      # The `resource` variable now holds the authenticated user object.
      ActsAsTenant.current_tenant = resource.firm
       # Renders a success message with the user's data using the `UserBlueprint`.
       # The `session_view` is specified to ensure only relevant data is included
       # and to prevent a circular dependency with other blueprints.
      user_data = {
        message: "Logged in successfully.",

        data: UserBlueprint.render_as_hash(resource, view: :session_view)
      }

      render json: user_data, status: :ok
    else
      # --- Failed Login Path ---
      # This block is executed if `warden.authenticate` returns a falsy value.
      # Use the standardized helper for a consistent error response.
      render_resource_errors(resource)
    end

  # Rescues from `ActionController::ParameterMissing` errors, which are raised
  # when the `user` key is missing from the request payload. This provides
  # a clean `400 Bad Request` response for invalid requests.
  rescue ActionController::ParameterMissing
    render json: { error: "Missing or invalid parameters in the request." }, status: :bad_request
  end

  # Overrides Devise's default method for responding to a successful logout.
  # This provides a custom, API-specific response.
  def respond_to_on_destroy
    # Returns a `204 No Content` status, which is the standard HTTP response
    # for a successful deletion or action that doesn't return a body.
    head :no_content
  end

  protected

  # A private method that returns the authentication options required by Warden.
  # It specifies the scope (`:user` in this case) to ensure Devise authenticates
  # against the correct model.
  def auth_options
    { scope: resource_name }
  end

  def force_json
    request.format = :json
  end
end
