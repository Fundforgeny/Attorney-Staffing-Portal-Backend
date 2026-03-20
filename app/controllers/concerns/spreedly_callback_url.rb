# Spreedly validates callback_url and redirect_url (3DS). Localhost / wrong host fails like callback.
#
# SPREEDLY_CALLBACK_BASE_URL — public origin of THIS API (no path), e.g. https://xxxx.ngrok-free.app
# SPREEDLY_3DS_RETURN_URL — optional full redirect after challenge (scheme + host + path)
# SPREEDLY_REDIRECT_BASE_URL — public origin of the FRONTEND (no path) when FRONTEND_APP_URL is still localhost
module SpreedlyCallbackUrl
  extend ActiveSupport::Concern

  private

  def spreedly_api_base_url
    explicit = ENV["SPREEDLY_CALLBACK_BASE_URL"].to_s.strip.presence
    return explicit.chomp("/") if explicit

    request.base_url
  end

  def spreedly_three_ds_callback_url(callback_token)
    "#{spreedly_api_base_url}/api/v1/payments/3ds/callback?callback_token=#{callback_token}"
  end

  def spreedly_three_ds_redirect_url
    explicit = ENV["SPREEDLY_3DS_RETURN_URL"].to_s.strip.presence
    return explicit if explicit

    base = ENV["SPREEDLY_REDIRECT_BASE_URL"].to_s.strip.presence ||
           ENV["FRONTEND_APP_URL"].to_s.strip.presence ||
           "http://localhost:5173"
    "#{base.chomp('/')}/pay/3ds-complete"
  end
end
