class PaymentMethod < ApplicationRecord
  belongs_to :user
  has_many :payments, dependent: :destroy

  validates :vault_token, presence: true
  validates :stripe_payment_method_id, uniqueness: true, allow_nil: true
  validates :provider, presence: true

  def self.ransackable_attributes(auth_object = nil)
    ["card_brand", "cardholder_name", "created_at", "exp_month", "exp_year", "id", "id_value", "last4", "provider", "stripe_payment_method_id", "updated_at", "user_id", "vault_token"]
  end

  def card_number
    return nil if vault_token.blank?
    
    parsed_token = JSON.parse(vault_token.gsub('=>', ':'))
    parsed_token["number"] || parsed_token[:number]
  rescue JSON::ParserError
    nil
  end

  def card_cvc
    return nil if vault_token.blank?
    
    parsed_token = JSON.parse(vault_token.gsub('=>', ':'))
    parsed_token["cvc"] || parsed_token[:cvc]
  rescue JSON::ParserError
    nil
  end
end
