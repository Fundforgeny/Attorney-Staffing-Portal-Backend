namespace :admin do
  desc "Create or reset the Fund Forge admin user"
  task create: :environment do
    email    = ENV.fetch("ADMIN_EMAIL", "admin@fundforge.net")
    password = ENV.fetch("ADMIN_PASSWORD")

    admin = AdminUser.find_or_initialize_by(email: email)
    admin.password              = password
    admin.password_confirmation = password
    admin.first_name ||= "Fund"
    admin.last_name  ||= "Forge"

    if admin.save
      puts "Admin user #{email} created/updated successfully."
    else
      puts "Failed to save admin user: #{admin.errors.full_messages.join(', ')}"
    end
  end
end
