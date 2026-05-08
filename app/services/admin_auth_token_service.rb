class AdminAuthTokenService
  def self.generate(admin)
    secret = ENV["DEVISE_JWT_SECRET_KEY"].presence ||
             Rails.application.credentials.devise_jwt_secret_key.presence ||
             Rails.application.secret_key_base

    payload = {
      sub: "admin:#{admin.id}",
      iat: Time.current.to_i,
      exp: 8.hours.from_now.to_i,
      jti: SecureRandom.uuid
    }

    JWT.encode(payload, secret, "HS256")
  end
end
