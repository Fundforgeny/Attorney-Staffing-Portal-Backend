class Admin::SessionsController < Devise::SessionsController
  skip_before_action :verify_authenticity_token, only: [:create, :destroy]
  
  def new
    super
  end
  
  def create
    self.resource = warden.authenticate!(auth_options)
    set_flash_message!(:notice, :signed_in)
    sign_in(resource_name, resource)
    
    # Check if user is super admin
    unless resource.super_admin?
      sign_out(resource)
      flash[:alert] = "Access denied. Super admin privileges required."
      redirect_to new_admin_session_path and return
    end
    
    yield resource if block_given?
    respond_with resource, location: after_sign_in_path_for(resource)
  end
  
  def destroy
    super
  end
  
  protected
  
  def after_sign_in_path_for(resource)
    admin_root_path
  end
  
  def after_sign_out_path_for(resource_or_scope)
    new_admin_session_path
  end
end
