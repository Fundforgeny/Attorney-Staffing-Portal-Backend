class Plan < ApplicationRecord
	belongs_to :user
	has_one :agreement, dependent: :destroy
  has_many :payments, dependent: :destroy

	enum :status, { active: 0, completed: 1, cancelled: 2 }, default: :active
end
