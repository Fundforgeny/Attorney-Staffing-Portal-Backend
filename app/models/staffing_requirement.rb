class StaffingRequirement < ApplicationRecord
  STATUSES = %w[draft ready internal_outreach indeed_sourcing interviewing staffed paused canceled].freeze
  URGENCIES = %w[standard urgent critical].freeze

  belongs_to :case

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :urgency, presence: true, inclusion: { in: URGENCIES }
  validates :target_interview_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  scope :active, -> { where(status: %w[ready internal_outreach indeed_sourcing interviewing]) }
  scope :staffed, -> { where(status: "staffed") }

  def requires_state_license?
    required_license_states.any?
  end

  def requires_federal_court_admission?
    federal_court_admissions.any?
  end
end
