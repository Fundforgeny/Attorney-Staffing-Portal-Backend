require "base64"
require "openssl"
require "securerandom"

module Spreedly
  class IframeSecurityService
    def self.configured?
      bundle = certificate_bundle
      bundle.present? && bundle[:certificate_token].present? && bundle[:private_key_pem].present?
    end

    def self.payload
      return { enabled: false } unless configured?

      nonce = SecureRandom.uuid
      timestamp = Time.current.to_i.to_s
      certificate_token = certificate_bundle.fetch(:certificate_token)

      {
        enabled: true,
        nonce: nonce,
        timestamp: timestamp,
        certificate_token: certificate_token,
        signature: sign(nonce, timestamp, certificate_token)
      }
    end

    def self.certificate_token
      ENV["SPREEDLY_IFRAME_CERTIFICATE_TOKEN"].presence ||
        ENV["SPREEDLY_CERTIFICATE_TOKEN"].presence
    end

    def self.private_key_pem
      raw_private_key = ENV["SPREEDLY_IFRAME_PRIVATE_KEY"].presence ||
                        ENV["SPREEDLY_PRIVATE_KEY"].presence
      raw_private_key&.gsub('\n', "\n")
    end

    def self.certificate_bundle
      if certificate_token.present? && private_key_pem.present?
        return {
          certificate_token: certificate_token,
          private_key_pem: private_key_pem
        }
      end

      generated_certificate_bundle
    end

    def self.generated_certificate_bundle
      Rails.cache.fetch("spreedly_iframe_security_certificate_bundle", expires_in: 12.hours) do
        generate_and_upload_certificate_bundle
      end
    end

    def self.generate_and_upload_certificate_bundle
      private_key = OpenSSL::PKey::RSA.new(3072)
      certificate = OpenSSL::X509::Certificate.new
      certificate.version = 2
      certificate.serial = SecureRandom.random_number(2**128)

      name = OpenSSL::X509::Name.parse("/C=US/O=Fund Forge/CN=iframe-security.local")
      certificate.subject = name
      certificate.issuer = name
      certificate.public_key = private_key.public_key
      certificate.not_before = Time.current
      certificate.not_after = 30.days.from_now

      extension_factory = OpenSSL::X509::ExtensionFactory.new
      extension_factory.subject_certificate = certificate
      extension_factory.issuer_certificate = certificate
      certificate.add_extension(extension_factory.create_extension("basicConstraints", "CA:TRUE", true))
      certificate.add_extension(extension_factory.create_extension("keyUsage", "digitalSignature,keyEncipherment", true))
      certificate.add_extension(extension_factory.create_extension("subjectKeyIdentifier", "hash"))
      certificate.add_extension(extension_factory.create_extension("authorityKeyIdentifier", "keyid:always,issuer:always"))
      certificate.sign(private_key, OpenSSL::Digest::SHA256.new)

      response = Spreedly::Client.new.post(
        "/certificates",
        body: {
          certificate: {
            pem: certificate.to_pem,
            level: "environment"
          }
        }
      )

      {
        certificate_token: response.dig("certificate", "token"),
        private_key_pem: private_key.to_pem
      }
    end

    def self.sign(nonce, timestamp, certificate_token)
      payload = "#{nonce}#{timestamp}#{certificate_token}"
      private_key = OpenSSL::PKey.read(certificate_bundle.fetch(:private_key_pem))
      Base64.strict_encode64(private_key.sign(OpenSSL::Digest::SHA256.new, payload))
    end

    private_class_method :sign, :generated_certificate_bundle, :generate_and_upload_certificate_bundle
  end
end
