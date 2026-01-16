class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # CSRF protection for HTML forms (For ActiveAdmin)
  protect_from_forgery with: :exception

  # Devise session-based auth for AdminUsers (For ActiveAdmin)
  before_action :authenticate_admin_user!, if: :active_admin_controller?

  # It wraps every Active Admin request in a block that temporarily disables `ActsAsTenant`.
  # Needed because Admin Users need to view or manage data across all locations (tenants) in the system, not just within a single one.
  around_action :with_tenant_for_admin, if: :active_admin_controller?

  private

  # Check if the current controller is part of the Active Admin interface by checking
  # if it inherits from `ActiveAdmin::BaseController` in its ancestry chain.
  # This allows the `before_action` and `around_action` to be applied conditionally.
  # We exclude the admin sessions controller to avoid redirect loops.
  def active_admin_controller?
    self.class.ancestors.include?(ActiveAdmin::BaseController)
  end

  # It uses `ActsAsTenant.without_tenant` to ensure that the code inside the block
  # (which is the controller action itself, passed in via `yield`)
  # is executed without any tenant scoping.
  def with_tenant_for_admin
    ActsAsTenant.without_tenant do
      yield
    end
  end
end
