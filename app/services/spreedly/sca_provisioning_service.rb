# One-off provisioning: Merchant Profile + SCA Provider (3DS2 Global).
# rails c: Spreedly::ScaProvisioningService.new.provision_from_env!
module Spreedly
  class ScaProvisioningService
    DEFAULT_CARD_BRANDS = %w[visa mastercard amex discover].freeze

    def initialize(client: Spreedly::Client.new)
      @client = client
    end

    def provision_from_env!
      provision!(
        merchant_name: env!("SPREEDLY_3DS_MERCHANT_NAME"),
        country_code: ENV.fetch("SPREEDLY_3DS_COUNTRY_CODE", "840"),
        acquirer_merchant_id: env!("SPREEDLY_3DS_ACQUIRER_MERCHANT_ID"),
        mcc: env!("SPREEDLY_3DS_MCC"),
        acquirer_bin: env!("SPREEDLY_3DS_ACQUIRER_BIN"),
        merchant_url: env!("SPREEDLY_3DS_MERCHANT_URL"),
        description: ENV["SPREEDLY_3DS_MERCHANT_PROFILE_DESCRIPTION"].presence,
        sandbox: ActiveModel::Type::Boolean.new.cast(ENV.fetch("SPREEDLY_3DS_SCA_SANDBOX", "true")),
        sca_type: sca_type_from_env,
        card_brands: card_brands_from_env
      )
    end

    def provision!(merchant_name:, country_code:, acquirer_merchant_id:, mcc:, acquirer_bin:, merchant_url:,
                   description: nil, sandbox:, sca_type:, card_brands: DEFAULT_CARD_BRANDS, per_brand_mids: nil)
      brands = Array(card_brands).map(&:to_s).presence || DEFAULT_CARD_BRANDS

      mp_response = @client.post("/merchant_profiles.json", body: build_merchant_profile(
        merchant_name: merchant_name,
        country_code: country_code.to_s,
        mcc: mcc.to_s,
        acquirer_merchant_id: acquirer_merchant_id.to_s,
        description: description,
        brands: brands,
        per_brand_mids: per_brand_mids
      ))

      merchant_profile = mp_response["merchant_profile"] || {}
      merchant_profile_token = merchant_profile["token"].presence
      raise Error, "Merchant profile response missing token: #{mp_response.inspect}" if merchant_profile_token.blank?

      sca_response = @client.post("/sca/providers.json", body: build_sca_provider(
        merchant_profile_key: merchant_profile_token,
        type: sca_type.to_s,
        sandbox: sandbox,
        acquirer_bin: acquirer_bin.to_s,
        merchant_url: merchant_url.to_s,
        brands: brands
      ))

      sca_provider = sca_response["sca_provider"] || {}
      sca_token = sca_provider["token"].presence
      raise Error, "SCA provider response missing token: #{sca_response.inspect}" if sca_token.blank?

      {
        merchant_profile_token: merchant_profile_token,
        sca_provider_token: sca_token,
        merchant_profile: merchant_profile,
        sca_provider: sca_provider
      }
    end

    private

    def env!(key)
      ENV[key].presence || raise(Error, "Missing required ENV #{key}")
    end

    def sca_type_from_env
      ENV["SPREEDLY_3DS_SCA_TYPE"].presence || (
        ActiveModel::Type::Boolean.new.cast(ENV.fetch("SPREEDLY_3DS_SCA_SANDBOX", "true")) ? "test" : "spreedly"
      )
    end

    def card_brands_from_env
      raw = ENV["SPREEDLY_3DS_CARD_BRANDS"].to_s.strip
      return DEFAULT_CARD_BRANDS if raw.blank?

      raw.split(",").map(&:strip).reject(&:blank?)
    end

    def build_merchant_profile(merchant_name:, country_code:, mcc:, acquirer_merchant_id:, description:, brands:, per_brand_mids:)
      profile = {}
      profile["description"] = description if description.present?

      brands.each do |brand|
        mid = per_brand_mids&.dig(brand) || per_brand_mids&.dig(brand.to_sym) || acquirer_merchant_id
        profile[brand] = {
          "acquirer_merchant_id" => mid,
          "merchant_name" => merchant_name,
          "country_code" => country_code,
          "mcc" => mcc
        }
      end

      { "merchant_profile" => profile }
    end

    def build_sca_provider(merchant_profile_key:, type:, sandbox:, acquirer_bin:, merchant_url:, brands:)
      sca = {
        "merchant_profile_key" => merchant_profile_key,
        "type" => type,
        "sandbox" => sandbox
      }

      brands.each do |brand|
        sca[brand] = {
          "acquirer_bin" => acquirer_bin,
          "merchant_url" => merchant_url
        }
      end

      { "sca_provider" => sca }
    end
  end
end
