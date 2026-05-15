class ExternalSyncRecord < ApplicationRecord
  PROVIDERS = %w[ghl clio indeed titans_app].freeze
  STATUSES = %w[pending synced failed skipped].freeze

  belongs_to :syncable, polymorphic: true

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :external_id, presence: true
  validates :external_object_type, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :external_id,
            uniqueness: { scope: [:provider, :external_object_type], case_sensitive: false }

  scope :for_provider, ->(provider) { where(provider: provider) }
  scope :failed, -> { where(status: "failed") }
  scope :synced, -> { where(status: "synced") }

  def mark_synced!(payload_hash: nil, synced_at: Time.current)
    update!(
      status: "synced",
      last_error: nil,
      last_payload_hash: payload_hash || last_payload_hash,
      last_synced_at: synced_at
    )
  end

  def mark_failed!(error)
    update!(status: "failed", last_error: error.to_s)
  end
end
