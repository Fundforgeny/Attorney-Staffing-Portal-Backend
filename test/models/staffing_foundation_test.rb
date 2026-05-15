require "test_helper"

class StaffingFoundationTest < ActiveSupport::TestCase
  test "case model exposes canonical staffing associations" do
    assert_includes Case.reflect_on_all_associations.map(&:name), :case_intakes
    assert_includes Case.reflect_on_all_associations.map(&:name), :related_parties
    assert_includes Case.reflect_on_all_associations.map(&:name), :case_tasks
    assert_includes Case.reflect_on_all_associations.map(&:name), :staffing_requirements
    assert_includes Case.reflect_on_all_associations.map(&:name), :external_sync_records
  end

  test "case validates title and staffing status" do
    matter = Case.new(staffing_status: nil)

    assert_not matter.valid?
    assert_includes matter.errors[:title], "can't be blank"
    assert_includes matter.errors[:staffing_status], "can't be blank"
  end

  test "case intake validates review status, source, and confidence range" do
    intake = CaseIntake.new(source: "invalid", review_status: "invalid", confidence: 2)

    assert_not intake.valid?
    assert intake.errors[:source].present?
    assert intake.errors[:review_status].present?
    assert intake.errors[:confidence].present?
  end

  test "staffing requirement validates status urgency and target interview count" do
    requirement = StaffingRequirement.new(status: "bad", urgency: "bad", target_interview_count: 0)

    assert_not requirement.valid?
    assert requirement.errors[:status].present?
    assert requirement.errors[:urgency].present?
    assert requirement.errors[:target_interview_count].present?
  end

  test "field mapping validates provider direction and external id" do
    mapping = FieldMapping.new(provider: "bad", direction: "bad")

    assert_not mapping.valid?
    assert mapping.errors[:provider].present?
    assert mapping.errors[:direction].present?
    assert mapping.errors[:canonical_attribute].present?
    assert mapping.errors[:external_field_id].present?
  end

  test "external sync record validates provider status and external identifiers" do
    record = ExternalSyncRecord.new(provider: "bad", status: "bad")

    assert_not record.valid?
    assert record.errors[:provider].present?
    assert record.errors[:status].present?
    assert record.errors[:external_id].present?
    assert record.errors[:external_object_type].present?
  end
end
