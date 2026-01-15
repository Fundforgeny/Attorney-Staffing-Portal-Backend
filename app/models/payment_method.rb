class PaymentMethod < ApplicationRecord
  belongs_to :user
  has_many :payments

  validates :vault_token, presence: true
  validates :stripe_payment_method_id, uniqueness: true, allow_nil: true
  validates :provider, presence: true

  def card_number
    return nil if vault_token.blank?
    
    parsed_token = JSON.parse(vault_token.gsub('=>', ':'))
    parsed_token["number"] || parsed_token[:number]
  rescue JSON::ParserError
    nil
  end
end
