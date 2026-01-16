class Firm < ApplicationRecord
  has_many :firm_users, dependent: :destroy
  has_many :users, through: :firm_users

  has_many :attorney_profiles, dependent: :destroy
  has_many :client_profiles, dependent: :destroy
  has_one_attached :logo

  # Define which attributes are searchable by Ransack
  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "description", "id", "id_value", "logo", "name", "primary_color", "secondary_color", "updated_at"]
  end
end
