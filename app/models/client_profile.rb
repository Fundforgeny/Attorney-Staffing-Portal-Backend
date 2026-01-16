# app/models/client_profile.rb
class ClientProfile < ApplicationRecord
  belongs_to :user
  belongs_to :firm, optional: true

  def self.ransackable_attributes(auth_object = nil)
    ["additional_info", "business_name", "created_at", "employer_name", "ever_been_convicted", "firm_id", "ghl_contact_id", "id", "is_employed", "service_number", "updated_at", "user_id", "work_hours_per_week"]
  end
end
