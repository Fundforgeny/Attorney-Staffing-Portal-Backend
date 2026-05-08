class AdminMailer < ApplicationMailer
  default from: "no-reply@fundforge.net"

  def login_link(admin, login_link)
    @admin = admin
    @login_link = login_link

    mail(to: admin.email, subject: "Your Fund Forge admin login link")
  end
end
