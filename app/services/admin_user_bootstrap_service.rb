class AdminUserBootstrapService
  DEFAULT_ALLOWED_EMAILS = ["contact@fundforge.net"].freeze
  DEFAULT_CONTACT_NUMBER = "+15555550100"

  def self.find_or_bootstrap!(email)
    normalized_email = email.to_s.strip.downcase
    admin = AdminUser.find_by(email: normalized_email)
    return admin if admin.present?

    unless allowed_email?(normalized_email)
      raise ActiveRecord::RecordNotFound, "Admin user not found"
    end

    first_name, last_name = normalized_email.split("@").first.to_s.split(/[._-]/, 2)
    password = SecureRandom.urlsafe_base64(32)
    AdminUser.create!(
      email: normalized_email,
      password: password,
      password_confirmation: password,
      first_name: first_name.presence&.titleize || "Fund",
      last_name: last_name.presence&.titleize || "Forge",
      contact_number: ENV.fetch("ADMIN_BOOTSTRAP_CONTACT_NUMBER", DEFAULT_CONTACT_NUMBER)
    )
  end

  def self.allowed_email?(email)
    allowed_admin_emails.include?(email)
  end

  def self.allowed_admin_emails
    raw = ENV["ADMIN_MAGIC_LINK_EMAILS"].to_s
    configured = raw.split(",").map { |value| value.strip.downcase }.reject(&:blank?)
    configured.presence || DEFAULT_ALLOWED_EMAILS
  end
end
