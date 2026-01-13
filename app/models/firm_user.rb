# app/models/firm_user.rb
class FirmUser < ApplicationRecord
  belongs_to :firm
  belongs_to :user

  enum :role, { member: 0, admin: 1 }

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "firm_id", "id", "role", "updated_at", "user_id"]
  end
end
