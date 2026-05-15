class CaseIntake < ApplicationRecord
  REVIEW_STATUSES = %w[pending_review approved rejected needs_more_information].freeze
  SOURCES = %w[manual ghl clio indeed titans_app].freeze

  belongs_to :case
  belongs_to :reviewed_by, class_name: "User", optional: true

  has_one_attached :intake_form
  has_one_attached :call_recording
  has_one_attached :matter_packet

  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :review_status, presence: true, inclusion: { in: REVIEW_STATUSES }
  validates :confidence,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
            allow_nil: true

  scope :pending_review, -> { where(review_status: "pending_review") }
  scope :approved, -> { where(review_status: "approved") }

  def reviewed?
    reviewed_at.present? || reviewed_by_id.present? || review_status.in?(%w[approved rejected])
  end
end
