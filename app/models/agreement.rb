class Agreement < ApplicationRecord
	belongs_to :user
	belongs_to :plan

	has_one_attached :pdf
	has_one_attached :signature

	def self.ransackable_associations(auth_object = nil)
    %w[user plan]
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id user_id plan_id signed_at created_at updated_at]
  end
end
