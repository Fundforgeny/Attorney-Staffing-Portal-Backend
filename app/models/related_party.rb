class RelatedParty < ApplicationRecord
  ROLES = %w[unknown client plaintiff defendant opposing_party counsel witness business_entity court other].freeze

  belongs_to :case
  has_many :external_sync_records, as: :syncable, dependent: :destroy

  validates :name, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }

  def self.ransackable_attributes(auth_object = nil)
    [
      "case_id", "clio_contact_id", "counsel_email", "counsel_name", "counsel_phone",
      "created_at", "custom_data", "email", "id", "name", "phone",
      "represented_status", "role", "updated_at"
    ]
  end
end
