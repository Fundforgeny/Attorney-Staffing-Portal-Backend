class PaymentMethod < ApplicationRecord
  MAX_PAYMENT_METHODS_PER_USER = 20

  belongs_to :user
  has_many :payments, dependent: :destroy
  has_many :payment_3ds_sessions, dependent: :destroy

  validates :stripe_payment_method_id, uniqueness: true, allow_nil: true
  validates :provider, presence: true
  validates :last4, length: { is: 4 }, allow_blank: true
  validates :exp_month, inclusion: { in: 1..12 }, allow_nil: true
  validates :exp_year, numericality: { only_integer: true, greater_than_or_equal_to: 2000 }, allow_nil: true
  validate :within_payment_method_limit, on: :create

  scope :ordered_for_user, -> { order(is_default: :desc, created_at: :desc) }

  def self.ransackable_attributes(auth_object = nil)
    ["card_brand", "cardholder_name", "created_at", "exp_month", "exp_year", "id", "id_value", "is_default", "last4", "last_updated_via_spreedly_at", "provider", "spreedly_redacted_at", "stripe_payment_method_id", "updated_at", "user_id", "vault_token"]
  end

  private

  def within_payment_method_limit
    return if user.blank?
    return if user.payment_methods.count < MAX_PAYMENT_METHODS_PER_USER

    errors.add(:base, "You can only add up to #{MAX_PAYMENT_METHODS_PER_USER} payment methods")
  end
end
