class CustomDeviseMailer < Devise::Mailer
  default from: 'please-change-me-at-config-initializers-devise@example.com'
  
  # Override any methods that need to generate URLs without tenant scoping
  # This mailer doesn't inherit from ApplicationController, so it won't have tenant issues
  
  def confirmation_instructions(record, token, opts = {})
    @confirmation_url = confirmation_url(record, opts)
    @resource = record
    super
  end
  
  def reset_password_instructions(record, token, opts = {})
    super
  end
  
  def unlock_instructions(record, token, opts = {})
    super
  end
end
