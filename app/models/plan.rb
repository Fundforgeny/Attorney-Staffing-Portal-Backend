class Plan < ApplicationRecord
	belongs_to :user
	has_one :agreement, dependent: :destroy
  has_many :payments, dependent: :destroy

	enum :status, { active: 0, completed: 1, cancelled: 2 }, default: :active

	def self.ransackable_attributes(auth_object = nil)
    [
      "id",
      "name",
      "duration",
      "total_payment",
      "total_interest_amount",
      "monthly_payment",
      "monthly_interest_amount",
      "down_payment",
      "status",
      "user_id",
      "created_at",
      "updated_at"
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    ["user", "agreements"]
  end

  def remaining_balance_logic
    total_due = total_payment + total_interest_amount
    total_paid = payments.where(status: :succeeded).sum(:total_payment_including_fee)
    total_due - total_paid
  end
end
