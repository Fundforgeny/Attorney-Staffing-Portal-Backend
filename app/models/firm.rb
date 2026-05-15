class Firm < ApplicationRecord
  has_many :firm_users, dependent: :destroy
  has_many :users, through: :firm_users
  has_many :attorney_profiles, dependent: :destroy
  has_many :client_profiles, dependent: :destroy
  has_many :cases, dependent: :restrict_with_exception
  has_one_attached :logo

  # Define which attributes are searchable by Ransack
  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "description", "id", "id_value", "logo", "name", "primary_color", "secondary_color", "updated_at", "location_id", "ghl_api_key", "contact_id"]
  end

  # Scopes
  scope :fund_forge, -> { where(name: "Fund Forge") }

  # Class methods
  def self.fund_forge_firm
    find_by(name: "Fund Forge")
  end
end
