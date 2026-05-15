class Case < ApplicationRecord
  belongs_to :firm
  belongs_to :created_by, class_name: "User"
  belongs_to :assigned_user, class_name: "User", foreign_key: :user_id, optional: true
  belongs_to :client_user, class_name: "User", optional: true

  has_many :case_intakes, dependent: :destroy
  has_many :related_parties, dependent: :destroy
  has_many :case_tasks, dependent: :destroy
  has_many :staffing_requirements, dependent: :destroy
  has_many :external_sync_records, as: :syncable, dependent: :destroy

  validates :title, presence: true
  validates :status, length: { maximum: 255 }, allow_blank: true
  validates :matter_status, length: { maximum: 255 }, allow_blank: true
  validates :staffing_status, presence: true

  def self.ransackable_attributes(auth_object = nil)
    [
      "budget_amount", "client_user_id", "clio_matter_id", "close_date", "county",
      "created_at", "created_by_id", "custom_data", "description", "firm_id", "id",
      "jurisdiction", "matter_status", "open_date", "paralegal", "pay_amount",
      "pay_type", "practice_areas", "retainer_amount", "staffing_status", "status",
      "title", "updated_at", "user_id", "zip_code"
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    [
      "assigned_user", "case_intakes", "case_tasks", "client_user", "created_by",
      "external_sync_records", "firm", "related_parties", "staffing_requirements"
    ]
  end
end
