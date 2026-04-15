require "cgi"
require "digest"

class LoginLinkService
  class ConfigurationError < StandardError; end
  class InvalidTokenError < StandardError; end
  class ExpiredTokenError < StandardError; end
  class UsedTokenError < StandardError; end

  def initialize(user:)
    @user = user
  end

  def generate_link
    raw_token = SecureRandom.urlsafe_base64(32)
    token_digest = digest_token(raw_token)

    @user.login_link_tokens.create!(
      token_digest: token_digest,
      expires_at: Time.current + LoginLinkToken::EXPIRATION_WINDOW
    )

    "#{frontend_base_url}/customer/login-link?token=#{CGI.escape(raw_token)}"
  end

  def self.verify!(raw_token)
    candidate_tokens = normalized_token_candidates(raw_token)
    raise InvalidTokenError, "Token is required" if candidate_tokens.empty?

    token_digests = candidate_tokens.map { |token| digest_token(token) }.uniq
    login_link_token = LoginLinkToken.find_by(token_digest: token_digests)

    raise InvalidTokenError, "Invalid login link token" if login_link_token.nil?
    unless token_digests.any? { |digest| secure_compare(login_link_token.token_digest, digest) }
      raise InvalidTokenError, "Invalid login link token"
    end

    LoginLinkToken.transaction do
      login_link_token.lock!

      raise UsedTokenError, "This login link has already been used" if login_link_token.used?
      raise ExpiredTokenError, "This login link has expired" if login_link_token.expired?

      login_link_token.update!(used_at: Time.current)
    end

    login_link_token.user
  end

  def self.digest_token(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end

  def digest_token(raw_token)
    self.class.digest_token(raw_token)
  end

  def frontend_base_url
    # Frontend host is environment-specific and should be configured per deploy target.
    raw_url = (ENV["FRONTEND_APP_URL"] || "http://localhost:5173").to_s.strip
    raise ConfigurationError, "Missing FRONTEND_APP_URL configuration" if raw_url.blank?

    raw_url.chomp("/")
  end

  def self.secure_compare(left, right)
    ActiveSupport::SecurityUtils.secure_compare(left, right)
  end

  def self.normalized_token_candidates(raw_token)
    token = raw_token.to_s.strip
    return [] if token.blank?

    # Some clients may send URL-encoded token values or wrap the token in quotes.
    unquoted = token.delete_prefix("\"").delete_suffix("\"")
    decoded = CGI.unescape(unquoted)

    [token, unquoted, decoded, CGI.unescape(token)].map(&:strip).reject(&:blank?).uniq
  end

  private_class_method :secure_compare
end

