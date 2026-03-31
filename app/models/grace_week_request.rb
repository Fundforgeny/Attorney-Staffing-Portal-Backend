class GraceWeekRequest < ApplicationRecord
  belongs_to :plan
  belongs_to :user
  belongs_to :payment  # the original installment being split

  enum :status, { pending: 0, approved: 1, denied: 2 }

  validates :status,         presence: true
  validates :requested_at,   presence: true
  validates :half_amount,    numericality: { greater_than: 0 }, allow_nil: true
  validates :first_half_due, presence: true, if: :approved?
  validates :second_half_due, presence: true, if: :approved?

  scope :open,    -> { where(status: :pending) }
  scope :recent,  -> { order(requested_at: :desc) }

  # Can a client request a grace week for this plan right now?
  # Rules:
  #   - No existing pending/approved grace week on this plan
  #   - The plan has an overdue or upcoming payment within 3 days
  def self.eligible?(plan)
    return false if plan.grace_week_requests.where(status: [:pending, :approved]).exists?
    true
  end

  def fully_paid?
    halves_paid >= 2
  end

  def first_half_paid?
    halves_paid >= 1
  end
end
