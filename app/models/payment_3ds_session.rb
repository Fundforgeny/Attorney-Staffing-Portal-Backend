class Payment3dsSession < ApplicationRecord
  self.table_name = "payment_3ds_sessions"

  STATES = %w[pending challenged succeeded failed].freeze

  belongs_to :user
  belongs_to :plan
  belongs_to :payment
  belongs_to :payment_method

  validates :status, inclusion: { in: STATES }
  validates :callback_token, presence: true, uniqueness: true
  validates :spreedly_transaction_token, uniqueness: true, allow_nil: true
end


