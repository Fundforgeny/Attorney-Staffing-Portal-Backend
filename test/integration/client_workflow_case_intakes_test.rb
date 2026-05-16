require "test_helper"

class ClientWorkflowCaseIntakesTest < ActionDispatch::IntegrationTest
  setup do
    @original_token = ENV[Api::V1::Workflows::ClientCaseIntakesController::API_TOKEN_ENV]
    ENV[Api::V1::Workflows::ClientCaseIntakesController::API_TOKEN_ENV] = "test-workflow-token"
  end

  teardown do
    if @original_token.nil?
      ENV.delete(Api::V1::Workflows::ClientCaseIntakesController::API_TOKEN_ENV)
    else
      ENV[Api::V1::Workflows::ClientCaseIntakesController::API_TOKEN_ENV] = @original_token
    end
  end

  test "client workflow endpoint creates canonical case intake records" do
    assert_difference -> { Case.count }, 1 do
      assert_difference -> { CaseIntake.count }, 1 do
        assert_difference -> { StaffingRequirement.count }, 1 do
          post "/api/v1/workflows/client_case_intakes", params: workflow_payload, headers: auth_headers, as: :json
        end
      end
    end

    assert_response :created
    body = JSON.parse(response.body)
    data = body.fetch("data")

    assert_equal "Case intake created.", body.fetch("message")
    assert_equal "Jane Client SC Contract Matter", data.fetch("case").fetch("title")
    assert_equal "SC", data.fetch("case").fetch("jurisdiction")
    assert_equal ["SC"], data.fetch("staffing_requirement").fetch("required_license_states")
    assert_equal "pending_review", data.fetch("case_intake").fetch("review_status")

    matter = Case.find(data.fetch("case").fetch("id"))
    assert_equal "workflow-event-123", matter.custom_data.fetch("external_event_id")
    assert_equal "customer", matter.custom_data.fetch("contact_type_change").fetch("new_contact_type")
    assert_equal "google", matter.custom_data.fetch("ads_attribution").fetch("source")
    assert_equal 1, matter.related_parties.count
    assert_equal 1, matter.case_tasks.count
    assert_equal 1, matter.external_sync_records.count
  end

  test "client workflow endpoint updates the same case when the external event repeats" do
    post "/api/v1/workflows/client_case_intakes", params: workflow_payload, headers: auth_headers, as: :json
    assert_response :created

    updated_payload = workflow_payload.deep_dup
    updated_payload[:case][:budget_amount] = 7500
    updated_payload[:staffing_requirement][:urgency] = "critical"

    assert_no_difference -> { Case.count } do
      post "/api/v1/workflows/client_case_intakes", params: updated_payload, headers: auth_headers, as: :json
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Case intake updated.", body.fetch("message")
    assert_equal false, body.fetch("data").fetch("created")
    assert_equal 7500.0, body.fetch("data").fetch("case").fetch("budget_amount")
    assert_equal "critical", body.fetch("data").fetch("staffing_requirement").fetch("urgency")
  end

  test "client workflow endpoint can derive event id from contact type change trigger" do
    derived_payload = workflow_payload.deep_dup
    derived_payload.delete(:external_event_id)
    derived_payload[:source] = "ghl_contact_type_change"

    post "/api/v1/workflows/client_case_intakes", params: derived_payload, headers: auth_headers, as: :json

    assert_response :created
    data = JSON.parse(response.body).fetch("data")
    matter = Case.find(data.fetch("case").fetch("id"))
    assert_equal "contact_type_change:69273f4c-6f78-4fc4-9953-621497e018b6:contact-123:customer", matter.custom_data.fetch("external_event_id")
  end

  test "client workflow endpoint rejects missing or wrong token" do
    post "/api/v1/workflows/client_case_intakes", params: workflow_payload, as: :json
    assert_response :unauthorized

    post "/api/v1/workflows/client_case_intakes", params: workflow_payload, headers: { "X-Titans-Workflow-Token" => "wrong" }, as: :json
    assert_response :unauthorized
  end

  test "client workflow endpoint rejects incomplete payloads" do
    post "/api/v1/workflows/client_case_intakes", params: { external_event_id: "event-only" }, headers: auth_headers, as: :json

    assert_response :bad_request
    assert_equal "client.email is required", JSON.parse(response.body).fetch("message")
  end

  private

  def auth_headers
    { "X-Titans-Workflow-Token" => "test-workflow-token" }
  end

  def workflow_payload
    {
      external_event_id: "workflow-event-123",
      source: "ghl_client_workflow",
      workflow_id: "69273f4c-6f78-4fc4-9953-621497e018b6",
      workflow_name: "Client Paid - Open Matter",
      trigger: {
        type: "contact_type_change",
        field: "contact_type"
      },
      contact_type_change: {
        previous_contact_type: "lead",
        new_contact_type: "customer"
      },
      location_id: "titans-law-location",
      ghl_contact_id: "contact-123",
      ghl_opportunity_id: "opportunity-456",
      firm: { name: "Titans Law" },
      client: {
        email: "jane.client@example.com",
        first_name: "Jane",
        last_name: "Client",
        phone: "+14155552671"
      },
      payment: {
        retainer_amount: 5000,
        budget_amount: 5000
      },
      ads_attribution: {
        source: "google",
        campaign_id: "campaign-123",
        ad_group_id: "ad-group-456",
        ad_id: "ad-789",
        gclid: "test-gclid"
      },
      case: {
        title: "Jane Client SC Contract Matter",
        description: "Client paid for a South Carolina contract dispute matter.",
        jurisdiction: "SC",
        county: "Richland",
        zip_code: "29201",
        practice_areas: ["contract_dispute"],
        retainer_amount: 5000,
        budget_amount: 5000
      },
      intake: {
        transcript: "Client described a contract dispute and requested representation.",
        ai_extraction: {
          case_description: "South Carolina contract dispute intake.",
          next_steps: ["Open Clio matter", "Prepare staffing requirement"]
        }
      },
      related_parties: [
        { name: "ACME LLC", role: "opposing_party" }
      ],
      case_tasks: [
        { title: "Review intake packet", description: "Review AI extraction before Clio sync.", priority: "high", source: "ai" }
      ],
      staffing_requirement: {
        status: "ready",
        urgency: "urgent",
        required_license_states: ["SC"],
        practice_areas: ["contract_dispute"],
        county: "Richland",
        zip_code: "29201",
        target_interview_count: 5
      }
    }
  end
end
