class FieldMapping < ApplicationRecord
  PROVIDERS = %w[ghl clio indeed titans_app].freeze
  DIRECTIONS = %w[inbound outbound bidirectional].freeze

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :canonical_attribute, presence: true
  validates :external_field_id, presence: true
  validates :direction, presence: true, inclusion: { in: DIRECTIONS }
  validates :external_field_id,
            uniqueness: { scope: [:provider, :location_id], case_sensitive: false }

  scope :active, -> { where(active: true) }
  scope :for_provider, ->(provider) { where(provider: provider) }
  scope :for_location, ->(location_id) { where(location_id: location_id) }
end
