class PaymentMethod < ApplicationRecord
  belongs_to :user
  has_many :payments, dependent: :destroy

  validates :stripe_payment_method_id, uniqueness: true, allow_nil: true
  validates :provider, presence: true

  def self.ransackable_attributes(auth_object = nil)
    ["card_brand", "cardholder_name", "created_at", "exp_month", "exp_year", "id", "id_value", "last4", "provider", "stripe_payment_method_id", "updated_at", "user_id", "vault_token"]
  end
end
