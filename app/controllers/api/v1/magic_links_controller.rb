class Api::V1::MagicLinksController < ActionController::API
  include ApiResponse

  before_action :set_create_params, only: [:create_user_with_magic_link]
  before_action :set_validate_params, only: [:validate]

  def create_user_with_magic_link
    result = MagicLinkService.new(@user_params, @plan_params).create_user_and_magic_link
    
    render_success(
      data: {
        user_id: result[:user].id,
        email: result[:user].email,
        plan_id: result[:plan].id,
        magic_link: result[:magic_link],
        firm_id: result[:firm].id,
        firm_name: result[:firm].name
      },
      message: "User and plan created successfully with magic link",
      status: :created
    )
  rescue ArgumentError => e
    render_error(message: e.message, status: :not_found)
  rescue StandardError => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def validate
    result = validate_magic_link(@token)
    
    render_success(
      data: {
        user_id: result[:user].id,
        name: result[:user].full_name,
        email: result[:user].email,
        plan_id: result[:plan].id,
        down_payment: result[:plan].down_payment.to_i,
        total_payment: result[:plan].total_payment.to_i,
        status: result[:plan].status
      },
      message: "Magic link validated successfully",
      status: :ok
    )
  rescue ArgumentError => e
    render_error(message: e.message, status: :bad_request)
  rescue StandardError => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  private

  def set_create_params
    required_params = [:name, :email, :id, :retainer_amount, :down_payment, :location_id]
    missing_params = required_params.select { |param| params[param].blank? }
    render_error(message: "Missing required parameters: #{missing_params.join(', ')}", status: :bad_request) unless missing_params.empty?

    @user_params = params.permit(:name, :email, :phone)
    @plan_params = params.permit(:id, :retainer_amount, :down_payment, :location_id)
  end

  def set_validate_params
    @token = params[:token]
    render_error(message: "Token is required", status: :bad_request) if @token.blank?
  end

  def validate_magic_link(token)
    plan = Plan.find_by(magic_link_token: token)
    raise ArgumentError, "Plan not found" if plan.blank?

    user = User.find_by(id: plan.user_id)
    raise ArgumentError, "User not found" if user.blank?
    {
      user: user,
      plan: plan
    }
  end
end
