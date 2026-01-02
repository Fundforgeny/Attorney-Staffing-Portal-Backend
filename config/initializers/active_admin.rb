ActiveAdmin.setup do |config|
  config.site_title = "Staffing Portal Admin"
  config.site_title_link = "/admin"

  config.load_paths = [File.join(Rails.root, "app", "admin")]

  config.authentication_method = :authenticate_user!
  config.current_user_method = :current_user

  config.logout_link_path = "/admin/logout"
  config.logout_link_method = :delete

  # Comments
  config.comments = false
  
  # Breadcrumbs
  config.breadcrumb = true
end
