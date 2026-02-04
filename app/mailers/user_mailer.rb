class UserMailer < ApplicationMailer
  default from: "no-reply@staffingportal.com"

  def confirmation_instructions(user, token, opts = {})
    @resource = user
    @confirmation_url = "#{ENV['FRONTEND_BASE_URL']}/create-password?confirmation_token=#{token}"

    mail(to: user.email, subject: "Confirmation Instructions")
  end

  def reset_password_instructions(user, token, opts = {})
    @reset_password_url = "#{ENV['FRONTEND_BASE_URL']}/reset-password?reset_password_token=#{token}"

    mail(to: user.email, subject: "Reset Password Instructions")
  end
end
