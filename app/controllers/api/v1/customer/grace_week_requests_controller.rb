# Api::V1::Customer::GraceWeekRequestsController
#
# Allows a logged-in client to request a grace week for their current plan.
# The request goes into a :pending queue for admin review.
#
class Api::V1::Customer::GraceWeekRequestsController < ActionController::API
  include ApiResponse
  before_action :authenticate_customer!
  before_action :set_plan

  # POST /api/v1/customer/plans/:plan_id/grace_week_requests
  def create
    unless GraceWeekRequest.eligible?(@plan)
      return render_error(
        message: "A grace week request is already open or has already been used for this plan.",
        status:  :unprocessable_entity
      )
    end

    grace = GraceWeekService.request!(
      plan:   @plan,
      user:   current_customer,
      reason: params[:reason]
    )

    render_success(
      data:    serialize(grace),
      message: "Your grace week request has been submitted and is under review. You will be notified once approved."
    )
  rescue GraceWeekService::Error => e
    render_error(message: e.message, status: :unprocessable_entity)
  rescue StandardError => e
    Rails.logger.error("[GraceWeekRequests] #{e.class}: #{e.message}")
    render_error(message: "An unexpected error occurred.", status: :internal_server_error)
  end

  # GET /api/v1/customer/plans/:plan_id/grace_week_requests/status
  def status
    grace = @plan.grace_week_requests.recent.first
    if grace
      render_success(data: serialize(grace))
    else
      render_success(data: nil)
    end
  end

  private

  def authenticate_customer!
    token = request.headers["Authorization"]&.split(" ")&.last
    return render_error(message: "Unauthorized", status: :unauthorized) unless token.present?

    payload = Warden::JWTAuth::TokenDecoder.new.call(token)
    @current_customer = User.find_by(id: payload["sub"])
    render_error(message: "Unauthorized", status: :unauthorized) unless @current_customer
  rescue JWT::DecodeError, Warden::JWTAuth::Errors::RevokedToken
    render_error(message: "Session expired. Please log in again.", status: :unauthorized)
  end

  def current_customer
    @current_customer
  end

  def set_plan
    @plan = current_customer.plans.find_by(id: params[:plan_id])
    render_error(message: "Plan not found", status: :not_found) unless @plan
  end

  def serialize(grace)
    {
      id:              grace.id,
      status:          grace.status,
      reason:          grace.reason,
      half_amount:     grace.half_amount&.to_d,
      first_half_due:  grace.first_half_due,
      second_half_due: grace.second_half_due,
      halves_paid:     grace.halves_paid,
      admin_note:      grace.status == "denied" ? grace.admin_note : nil,
      requested_at:    grace.requested_at
    }
  end
end
