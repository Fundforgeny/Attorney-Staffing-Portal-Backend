class Api::V1::Admin::StaffingRequirementsController < Api::V1::Admin::BaseController
  before_action :set_staffing_requirement, only: [:show]

  # GET /api/v1/admin/staffing_requirements
  def index
    scope = StaffingRequirement.includes(case: [:firm, :client_user, :assigned_user])
                               .order(created_at: :desc)

    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(urgency: params[:urgency]) if params[:urgency].present?
    scope = scope.joins(:case).where(cases: { jurisdiction: params[:jurisdiction] }) if params[:jurisdiction].present?
    scope = apply_search(scope, params[:q]) if params[:q].present?

    paged = paginate(scope.distinct)

    render_success(
      data: paged.map { |requirement| staffing_requirement_row(requirement) },
      meta: pagination_meta(paged)
    )
  end

  # GET /api/v1/admin/staffing_requirements/:id
  def show
    render_success(data: staffing_requirement_detail(@staffing_requirement))
  end

  private

  def set_staffing_requirement
    @staffing_requirement = StaffingRequirement.includes(case: [:firm, :client_user, :assigned_user, :related_parties, :case_tasks]).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error(message: "Staffing requirement not found.", status: :not_found)
  end

  def apply_search(scope, raw_query)
    query = raw_query.to_s.strip
    return scope if query.blank?

    like_query = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"

    scope.joins(:case).where(
      "cases.title ILIKE :q OR cases.description ILIKE :q OR cases.jurisdiction ILIKE :q OR " \
      "cases.county ILIKE :q OR cases.zip_code ILIKE :q",
      q: like_query
    )
  end

  def staffing_requirement_row(requirement)
    matter = requirement.case

    {
      id: requirement.id,
      case_id: requirement.case_id,
      case_title: matter&.title,
      firm_id: matter&.firm_id,
      firm_name: matter&.firm&.name,
      client_user_id: matter&.client_user_id,
      client_name: matter&.client_user&.full_name,
      jurisdiction: matter&.jurisdiction,
      county: requirement.county.presence || matter&.county,
      zip_code: requirement.zip_code.presence || matter&.zip_code,
      status: requirement.status,
      urgency: requirement.urgency,
      required_license_states: requirement.required_license_states || [],
      federal_court_admissions: requirement.federal_court_admissions || [],
      practice_areas: requirement.practice_areas || [],
      residency_required: requirement.residency_required,
      target_interview_count: requirement.target_interview_count,
      case_staffing_status: matter&.staffing_status,
      case_matter_status: matter&.matter_status,
      created_at: requirement.created_at,
      updated_at: requirement.updated_at
    }
  end

  def staffing_requirement_detail(requirement)
    matter = requirement.case

    staffing_requirement_row(requirement).merge(
      case: matter ? case_summary(matter) : nil,
      related_parties_count: matter ? matter.related_parties.size : 0,
      open_case_tasks_count: matter ? matter.case_tasks.open_tasks.size : 0
    )
  end

  def case_summary(matter)
    {
      id: matter.id,
      title: matter.title,
      description: matter.description,
      jurisdiction: matter.jurisdiction,
      county: matter.county,
      zip_code: matter.zip_code,
      practice_areas: matter.practice_areas || [],
      status: matter.status,
      matter_status: matter.matter_status,
      staffing_status: matter.staffing_status,
      open_date: matter.open_date,
      close_date: matter.close_date,
      clio_matter_id: matter.clio_matter_id,
      assigned_user_id: matter.user_id,
      assigned_user_name: matter.assigned_user&.full_name
    }
  end
end
