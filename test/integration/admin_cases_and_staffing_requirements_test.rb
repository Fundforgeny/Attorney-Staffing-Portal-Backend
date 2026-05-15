require "test_helper"

class AdminCasesAndStaffingRequirementsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = AdminUser.create!(
      email: "staffing-admin@example.com",
      password: "Password123!",
      first_name: "Staffing",
      last_name: "Admin",
      contact_number: "+14155552671",
      role: :fund_forge_admin
    )

    @firm = Firm.create!(name: "Titans Law")
    @creator = User.create!(email: "creator@example.com", first_name: "Case", last_name: "Creator", user_type: :client)
    @client = User.create!(email: "client@example.com", first_name: "Client", last_name: "Example", user_type: :client)
    @attorney = User.create!(email: "attorney@example.com", first_name: "Attorney", last_name: "Example", user_type: :attorney)

    @case = Case.create!(
      firm: @firm,
      created_by: @creator,
      client_user: @client,
      assigned_user: @attorney,
      title: "Michael Jones South Carolina Civil Litigation",
      description: "Urgent South Carolina matter requiring civil litigation staffing.",
      jurisdiction: "SC",
      county: "Richland",
      zip_code: "29201",
      practice_areas: ["civil_litigation"],
      status: "open",
      matter_status: "initial_investigation",
      staffing_status: "not_started",
      retainer_amount: 5000,
      budget_amount: 5000,
      clio_matter_id: "clio-matter-123"
    )

    @requirement = StaffingRequirement.create!(
      case: @case,
      status: "ready",
      urgency: "urgent",
      required_license_states: ["SC"],
      practice_areas: ["civil_litigation"],
      county: "Richland",
      zip_code: "29201",
      target_interview_count: 5
    )
  end

  test "admin can list cases" do
    get "/api/v1/admin/cases", headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.fetch("data").length
    assert_equal @case.id, body.fetch("data").first.fetch("id")
    assert_equal "Michael Jones South Carolina Civil Litigation", body.fetch("data").first.fetch("title")
    assert_equal @requirement.id, body.fetch("data").first.fetch("latest_staffing_requirement_id")
  end

  test "admin can show case detail" do
    RelatedParty.create!(case: @case, name: "Opposing Party", role: "opposing_party")
    CaseTask.create!(case: @case, title: "Review intake packet", source: "ai", priority: "high")

    get "/api/v1/admin/cases/#{@case.id}", headers: auth_headers

    assert_response :success
    data = JSON.parse(response.body).fetch("data")
    assert_equal @case.id, data.fetch("id")
    assert_equal 1, data.fetch("related_parties").length
    assert_equal 1, data.fetch("case_tasks").length
    assert_equal 1, data.fetch("staffing_requirements").length
  end

  test "admin can list staffing requirements" do
    get "/api/v1/admin/staffing_requirements", headers: auth_headers

    assert_response :success
    data = JSON.parse(response.body).fetch("data")
    assert_equal 1, data.length
    assert_equal @requirement.id, data.first.fetch("id")
    assert_equal @case.id, data.first.fetch("case_id")
    assert_equal ["SC"], data.first.fetch("required_license_states")
  end

  test "admin can show staffing requirement detail" do
    CaseTask.create!(case: @case, title: "Call client", source: "manual", priority: "normal")

    get "/api/v1/admin/staffing_requirements/#{@requirement.id}", headers: auth_headers

    assert_response :success
    data = JSON.parse(response.body).fetch("data")
    assert_equal @requirement.id, data.fetch("id")
    assert_equal @case.id, data.fetch("case").fetch("id")
    assert_equal 1, data.fetch("open_case_tasks_count")
  end

  test "admin endpoints require authorization" do
    get "/api/v1/admin/cases"

    assert_response :unauthorized
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{AdminAuthTokenService.generate(@admin)}" }
  end
end
