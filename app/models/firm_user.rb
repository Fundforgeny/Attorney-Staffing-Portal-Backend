# app/models/firm_user.rb
class FirmUser < ApplicationRecord
  belongs_to :firm
  belongs_to :user

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "firm_id", "id", "ghl_fund_forge_id", "updated_at", "user_id", "contact_id"]
  end
end
