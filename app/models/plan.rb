class Plan < ApplicationRecord
	belongs_to :user
	has_one :agreement, dependent: :destroy
  has_many :payments, dependent: :destroy

	enum :status, {
    draft: 0,
    agreement_generated: 1,
    payment_pending: 2,
    paid: 3,
    failed: 4,
    expired: 5
  }, default: :draft

  # Backward-compatible scopes for legacy callers that still use old status names.
  scope :active, -> { where(status: statuses[:draft]) }
  scope :completed, -> { where(status: statuses[:paid]) }
  scope :cancelled, -> { where(status: statuses[:failed]) }

  validates :checkout_session_id, presence: true
  validates :total_payment, numericality: { greater_than: 0 }
  validates :down_payment, numericality: { greater_than_or_equal_to: 0 }
  validates :duration, inclusion: { in: [ 0, 3, 6, 9, 12 ] }, allow_nil: true

	def self.ransackable_attributes(auth_object = nil)
    [
      "id",
      "checkout_session_id",
      "name",
      "next_payment_at",
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
    total_due = total_payment_plan_amount
    total_paid = payments.where(status: :succeeded).sum(:total_payment_including_fee)
    total_due - total_paid
  end

  def payment_plan_selected?
    duration.to_i.positive?
  end

  def editable?
    !paid? && !expired?
  end

  def administration_fee_name
    PaymentPlanFeeCalculator::FEE_NAME
  end

  def administration_fee_percentage
    (PaymentPlanFeeCalculator::FEE_PERCENTAGE * 100).to_i
  end

  def administration_fee_amount
    (total_interest_amount || 0).to_d
  end

  def base_legal_fee_amount
    (total_payment || 0).to_d
  end

  def total_payment_plan_amount
    base_legal_fee_amount + administration_fee_amount
  end

  def calculated_next_payment_at
    payments
      .monthly_payment
      .where(status: [ Payment.statuses[:pending], Payment.statuses[:processing] ])
      .where.not(scheduled_at: nil)
      .order(:scheduled_at)
      .pick(:scheduled_at)
  end

  def next_scheduled_monthly_payment
    payments
      .monthly_payment
      .where(status: [ Payment.statuses[:pending], Payment.statuses[:processing] ])
      .where.not(scheduled_at: nil)
      .order(:scheduled_at)
      .first
  end

  def refresh_next_payment_at!
    return unless persisted?

    update_column(:next_payment_at, calculated_next_payment_at)
  end
end
