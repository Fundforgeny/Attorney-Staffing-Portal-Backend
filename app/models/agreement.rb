class Agreement < ApplicationRecord
	belongs_to :user
	belongs_to :plan

	has_one_attached :pdf
end
