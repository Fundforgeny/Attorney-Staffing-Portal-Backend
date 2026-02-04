class Payment < ApplicationRecord
  belongs_to :user
  belongs_to :payment_method
  belongs_to :plan

  def self.ransackable_associations(auth_object = nil)
    %w[user plan payment_method]
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[
      id payment_type status payment_amount charge_id
      scheduled_at paid_at created_at updated_at
      total_payment_including_fee transaction_fee
      user_id plan_id payment_method_id
    ]
  end

  enum :status, { pending: 0, processing: 1, succeeded: 2, failed: 3 }
  enum :payment_type, { down_payment: 0, monthly_payment: 1, full_payment: 2 }

  scope :due_today, -> { where(scheduled_at: Date.current.beginning_of_day..Date.current.end_of_day) }
end
