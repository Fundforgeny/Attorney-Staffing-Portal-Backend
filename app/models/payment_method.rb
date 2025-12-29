class PaymentMethod < ApplicationRecord
  belongs_to :user
  has_many :payments

  validates :vault_token, presence: true
  validates :stripe_payment_method_id, uniqueness: true, allow_nil: true
  validates :provider, presence: true
end
