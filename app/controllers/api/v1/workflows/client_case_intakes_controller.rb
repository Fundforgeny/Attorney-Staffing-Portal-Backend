class Api::V1::Workflows::ClientCaseIntakesController < ActionController::API
  include ApiResponse

  API_TOKEN_ENV = "TITANS_CLIENT_WORKFLOW_API_TOKEN".freeze

  before_action :authenticate_workflow!

  # POST /api/v1/workflows/client_case_intakes
  def create
    result = ClientWorkflowCaseIntakeService.new(workflow_payload).call

    render_success(
      data: response_payload(result),
      message: result.created ? "Case intake created." : "Case intake updated.",
      status: result.created ? :created : :ok
    )
  rescue ArgumentError => e
    render_error(message: e.message, status: :bad_request)
  rescue ActiveRecord::RecordInvalid => e
    render_error(errors: e.record.errors.full_messages, message: "Case intake could not be saved.", status: :unprocessable_entity)
  end

  private

  def authenticate_workflow!
    expected_token = ENV[API_TOKEN_ENV].presence
    provided_token = request.headers["X-Titans-Workflow-Token"].presence || bearer_token

    unless expected_token.present? && provided_token.present? && secure_compare(expected_token, provided_token)
      render_error(message: "Unauthorized", status: :unauthorized)
    end
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    return nil unless header.start_with?("Bearer ")

    header.split(" ", 2).last
  end

  def secure_compare(expected, provided)
    ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(expected),
      Digest::SHA256.hexdigest(provided)
    )
  end

  def workflow_payload
    params.permit!.to_h.except("controller", "action")
  end

  def response_payload(result)
    {
      case: case_payload(result.case_record),
      case_intake: case_intake_payload(result.case_intake),
      staffing_requirement: staffing_requirement_payload(result.staffing_requirement),
      created: result.created
    }
  end

  def case_payload(case_record)
    {
      id: case_record.id,
      title: case_record.title,
      client_user_id: case_record.client_user_id,
      firm_id: case_record.firm_id,
      jurisdiction: case_record.jurisdiction,
      county: case_record.county,
      zip_code: case_record.zip_code,
      practice_areas: case_record.practice_areas || [],
      matter_status: case_record.matter_status,
      staffing_status: case_record.staffing_status,
      retainer_amount: case_record.retainer_amount&.to_f,
      budget_amount: case_record.budget_amount&.to_f,
      clio_matter_id: case_record.clio_matter_id,
      created_at: case_record.created_at,
      updated_at: case_record.updated_at
    }
  end

  def case_intake_payload(case_intake)
    {
      id: case_intake.id,
      source: case_intake.source,
      review_status: case_intake.review_status,
      ghl_contact_id: case_intake.ghl_contact_id,
      ghl_opportunity_id: case_intake.ghl_opportunity_id,
      confidence: case_intake.confidence&.to_f,
      created_at: case_intake.created_at,
      updated_at: case_intake.updated_at
    }
  end

  def staffing_requirement_payload(requirement)
    return nil unless requirement

    {
      id: requirement.id,
      status: requirement.status,
      urgency: requirement.urgency,
      required_license_states: requirement.required_license_states || [],
      federal_court_admissions: requirement.federal_court_admissions || [],
      practice_areas: requirement.practice_areas || [],
      county: requirement.county,
      zip_code: requirement.zip_code,
      residency_required: requirement.residency_required,
      target_interview_count: requirement.target_interview_count,
      created_at: requirement.created_at,
      updated_at: requirement.updated_at
    }
  end
end
