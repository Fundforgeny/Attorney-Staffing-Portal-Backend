class CaseTask < ApplicationRecord
  PRIORITIES = %w[low normal high urgent].freeze
  STATUSES = %w[open in_progress completed canceled].freeze
  SOURCES = %w[manual ai clio ghl titans_app].freeze

  belongs_to :case
  belongs_to :owner, class_name: "User", optional: true
  has_many :external_sync_records, as: :syncable, dependent: :destroy

  validates :title, presence: true
  validates :priority, presence: true, inclusion: { in: PRIORITIES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :source, presence: true, inclusion: { in: SOURCES }

  scope :open_tasks, -> { where(status: "open") }
  scope :completed_tasks, -> { where(status: "completed") }
  scope :due_tasks, -> { where.not(due_at: nil).where("due_at <= ?", Time.current) }
end
