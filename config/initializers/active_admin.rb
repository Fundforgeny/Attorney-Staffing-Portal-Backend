ActiveAdmin.setup do |config|
  config.site_title = "Staffing Portal Admin"

  config.load_paths = [File.join(Rails.root, "app", "admin")]

  config.authentication_method = :authenticate_super_admin_user!
  config.current_user_method = :current_super_admin_user

  config.logout_link_path = :super_admin_sign_out_path
  config.logout_link_method = :delete
end
