class Api::V1::Admin::CasesController < Api::V1::Admin::BaseController
  before_action :set_case, only: [:show]

  # GET /api/v1/admin/cases
  def index
    scope = Case.includes(:firm, :client_user, :assigned_user, :created_by, :staffing_requirements)
                .order(created_at: :desc)

    scope = scope.where(staffing_status: params[:staffing_status]) if params[:staffing_status].present?
    scope = scope.where(matter_status: params[:matter_status]) if params[:matter_status].present?
    scope = scope.where(jurisdiction: params[:jurisdiction]) if params[:jurisdiction].present?
    scope = apply_search(scope, params[:q]) if params[:q].present?

    paged = paginate(scope.distinct)

    render_success(
      data: paged.map { |matter| case_row(matter) },
      meta: pagination_meta(paged)
    )
  end

  # GET /api/v1/admin/cases/:id
  def show
    render_success(data: case_detail(@case))
  end

  private

  def set_case
    @case = Case.includes(
      :firm,
      :client_user,
      :assigned_user,
      :created_by,
      :related_parties,
      :case_tasks,
      :case_intakes,
      :staffing_requirements,
      :external_sync_records
    ).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error(message: "Case not found.", status: :not_found)
  end

  def apply_search(scope, raw_query)
    query = raw_query.to_s.strip
    return scope if query.blank?

    like_query = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"

    scope.left_joins(:client_user, :assigned_user)
         .where(
           "cases.title ILIKE :q OR cases.description ILIKE :q OR cases.jurisdiction ILIKE :q OR " \
           "cases.county ILIKE :q OR cases.zip_code ILIKE :q OR cases.clio_matter_id ILIKE :q OR " \
           "client_users_cases.email ILIKE :q OR client_users_cases.first_name ILIKE :q OR " \
           "client_users_cases.last_name ILIKE :q OR assigned_users_cases.email ILIKE :q OR " \
           "assigned_users_cases.first_name ILIKE :q OR assigned_users_cases.last_name ILIKE :q",
           q: like_query
         )
  end

  def case_row(matter)
    requirement = matter.staffing_requirements.max_by(&:created_at)

    {
      id: matter.id,
      title: matter.title,
      description: matter.description,
      firm_id: matter.firm_id,
      firm_name: matter.firm&.name,
      client_user_id: matter.client_user_id,
      client_name: matter.client_user&.full_name,
      assigned_user_id: matter.user_id,
      assigned_user_name: matter.assigned_user&.full_name,
      jurisdiction: matter.jurisdiction,
      county: matter.county,
      zip_code: matter.zip_code,
      practice_areas: matter.practice_areas || [],
      status: matter.status,
      matter_status: matter.matter_status,
      staffing_status: matter.staffing_status,
      open_date: matter.open_date,
      close_date: matter.close_date,
      retainer_amount: matter.retainer_amount&.to_f,
      budget_amount: matter.budget_amount&.to_f,
      clio_matter_id: matter.clio_matter_id,
      latest_staffing_requirement_id: requirement&.id,
      latest_staffing_requirement_status: requirement&.status,
      created_at: matter.created_at,
      updated_at: matter.updated_at
    }
  end

  def case_detail(matter)
    case_row(matter).merge(
      related_parties: matter.related_parties.order(:created_at).map { |party| related_party_row(party) },
      case_tasks: matter.case_tasks.order(created_at: :desc).map { |task| case_task_row(task) },
      case_intakes: matter.case_intakes.order(created_at: :desc).map { |intake| case_intake_row(intake) },
      staffing_requirements: matter.staffing_requirements.order(created_at: :desc).map { |requirement| staffing_requirement_row(requirement) },
      external_sync_records: matter.external_sync_records.order(created_at: :desc).map { |record| external_sync_record_row(record) }
    )
  end

  def related_party_row(party)
    {
      id: party.id,
      name: party.name,
      role: party.role,
      email: party.email,
      phone: party.phone,
      represented_status: party.represented_status,
      counsel_name: party.counsel_name,
      clio_contact_id: party.clio_contact_id,
      created_at: party.created_at
    }
  end

  def case_task_row(task)
    {
      id: task.id,
      title: task.title,
      description: task.description,
      priority: task.priority,
      status: task.status,
      source: task.source,
      due_at: task.due_at,
      owner_id: task.owner_id,
      owner_name: task.owner&.full_name,
      clio_task_id: task.clio_task_id,
      created_at: task.created_at
    }
  end

  def case_intake_row(intake)
    {
      id: intake.id,
      source: intake.source,
      ghl_contact_id: intake.ghl_contact_id,
      ghl_opportunity_id: intake.ghl_opportunity_id,
      review_status: intake.review_status,
      confidence: intake.confidence&.to_f,
      reviewed_by_id: intake.reviewed_by_id,
      reviewed_at: intake.reviewed_at,
      has_intake_form: intake.intake_form.attached?,
      has_call_recording: intake.call_recording.attached?,
      has_matter_packet: intake.matter_packet.attached?,
      created_at: intake.created_at
    }
  end

  def staffing_requirement_row(requirement)
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

  def external_sync_record_row(record)
    {
      id: record.id,
      provider: record.provider,
      external_id: record.external_id,
      external_object_type: record.external_object_type,
      status: record.status,
      last_synced_at: record.last_synced_at,
      last_error: record.last_error,
      created_at: record.created_at
    }
  end
end
