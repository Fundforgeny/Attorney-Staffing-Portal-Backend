# app/models/attorney_profile.rb
class AttorneyProfile < ApplicationRecord
  belongs_to :user
  belongs_to :firm
  
  def self.ransackable_attributes(auth_object = nil)
    ["bar_number", "bio", "created_at", "firm_id", "ghl_contact_id", "id", "jurisdiction", "license_states", "practice_areas", "source", "specialties", "tags", "updated_at", "user_id", "years_experience"]
  end
end
