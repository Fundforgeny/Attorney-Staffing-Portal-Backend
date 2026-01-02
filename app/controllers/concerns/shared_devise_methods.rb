module Users::SharedDeviseMethods
  extend ActiveSupport::Concern

  included do
    respond_to :json
    skip_before_action :verify_authenticity_token
    before_action :set_tenant

    # Rescue from standard Rails errors for a consistent JSON response.
    rescue_from ActiveRecord::RecordNotFound do |e|
      render json: { error: e.message }, status: :not_found
    end

    rescue_from ActsAsTenant::Errors::NoTenantSet do
      render json: { error: "Tenant not specified or invalid" }, status: :unprocessable_entity
    end
  end

  protected

  # Standardized method for rendering validation errors from a resource.
  def render_resource_errors(resource)
    render json: { errors: resource.errors.full_messages }, status: :unprocessable_entity
  end

  # Helper method to check if the instructions were successfully sent.
  def successfully_sent?(resource)
    resource.errors.empty?
  end

  private

  # This is the method that ActsAsTenant's filter will call to get the tenant.
  def set_tenant
    if current_user&.firm
      ActsAsTenant.current_tenant = current_user.firm
    else
      ActsAsTenant.current_tenant = nil
    end
  end
end
