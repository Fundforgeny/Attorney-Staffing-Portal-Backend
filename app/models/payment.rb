class Payment < ApplicationRecord
  belongs_to :user
  belongs_to :payment_method
  belongs_to :plan

  enum :status, { pending: 0, processing: 1, succeeded: 2, failed: 3 }
  enum :payment_type, { down_payment: 0, monthly_payment: 1, one_time_payment: 2 }

  scope :due_today, -> { where(scheduled_at: Date.current.beginning_of_day..Date.current.end_of_day) }
end
