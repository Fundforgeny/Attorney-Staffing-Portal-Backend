require "test_helper"

class ConnectorConfigAndClioSyncTest < ActiveSupport::TestCase
  setup do
    @original_agency_key = ENV[GhlAgencyConfig::AGENCY_API_KEY_ENV]
    @original_default_location = ENV[GhlAgencyConfig::DEFAULT_LOCATION_ID_ENV]
    @original_titans_location = ENV[GhlAgencyConfig::TITANS_LAW_LOCATION_ID_ENV]
    @original_talent_key = ENV[TalentHubGhlConfig::API_KEY_ENV]
    @original_talent_location = ENV[TalentHubGhlConfig::LOCATION_ID_ENV]
    @original_clio_token = ENV[ClioConfig::ACCESS_TOKEN_ENV]
  end

  teardown do
    restore_env(GhlAgencyConfig::AGENCY_API_KEY_ENV, @original_agency_key)
    restore_env(GhlAgencyConfig::DEFAULT_LOCATION_ID_ENV, @original_default_location)
    restore_env(GhlAgencyConfig::TITANS_LAW_LOCATION_ID_ENV, @original_titans_location)
    restore_env(TalentHubGhlConfig::API_KEY_ENV, @original_talent_key)
    restore_env(TalentHubGhlConfig::LOCATION_ID_ENV, @original_talent_location)
    restore_env(ClioConfig::ACCESS_TOKEN_ENV, @original_clio_token)
  end

  test "agency GHL config uses agency key and explicit location" do
    ENV[GhlAgencyConfig::AGENCY_API_KEY_ENV] = "agency-token"
    ENV[GhlAgencyConfig::DEFAULT_LOCATION_ID_ENV] = "default-location"

    assert GhlAgencyConfig.configured?
    assert_nothing_raised { GhlAgencyConfig.require_config! }
    assert_instance_of GhlService, GhlAgencyConfig.ghl_service(location_id: "custom-location")
  end

  test "Talent Hub config can fall back to agency key while keeping Talent Hub location separate" do
    ENV.delete(TalentHubGhlConfig::API_KEY_ENV)
    ENV[GhlAgencyConfig::AGENCY_API_KEY_ENV] = "agency-token"
    ENV[TalentHubGhlConfig::LOCATION_ID_ENV] = "talent-hub-location"

    assert TalentHubGhlConfig.configured?
    assert_equal "agency-token", TalentHubGhlConfig.api_key
    assert_equal "talent-hub-location", TalentHubGhlConfig.location_id
  end

  test "Clio config reports readiness only when access token is present" do
    ENV.delete(ClioConfig::ACCESS_TOKEN_ENV)
    assert_not ClioConfig.configured?

    ENV[ClioConfig::ACCESS_TOKEN_ENV] = "clio-token"
    assert ClioConfig.configured?
  end

  test "Clio matter sync dry run builds deterministic operations from canonical case" do
    matter = build_case_with_staffing_records

    result = ClioMatterSyncService.new(matter).dry_run

    assert result.dry_run
    assert_not result.ready_for_live_sync
    actions = result.operations.map { |operation| operation[:action] }
    assert_includes actions, "find_or_create_contact"
    assert_includes actions, "create_matter"
    assert_includes actions, "create_note"
    assert_includes actions, "find_or_create_related_contact"
    assert_includes actions, "create_task"

    matter_operation = result.operations.detect { |operation| operation[:action] == "create_matter" }
    assert_equal "Workflow Sync Test Matter", matter_operation.dig(:payload, :custom_data, :title)
    assert_equal 5000.0, matter_operation.dig(:payload, :custom_data, :budget_amount)
  end

  private

  def build_case_with_staffing_records
    firm = Firm.create!(name: "Titans Law Connector Test")
    client = User.create!(email: "clio.client@example.com", first_name: "Clio", last_name: "Client", user_type: :client)
    matter = Case.create!(
      firm: firm,
      created_by: client,
      client_user: client,
      title: "Workflow Sync Test Matter",
      description: "Matter created for Clio dry-run testing.",
      jurisdiction: "SC",
      county: "Richland",
      zip_code: "29201",
      practice_areas: ["contract_dispute"],
      status: "open",
      matter_status: "intake_received",
      staffing_status: "not_started",
      open_date: Date.current,
      retainer_amount: 5000,
      budget_amount: 5000
    )
    matter.case_intakes.create!(source: "ghl_contact_type_change", review_status: "pending_review", ai_extraction: { summary: "AI summary" })
    matter.related_parties.create!(name: "Opposing Party LLC", role: "opposing_party")
    matter.case_tasks.create!(title: "Review intake", priority: "high", source: "ai")
    matter
  end

  def restore_env(key, value)
    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end
  end
end
