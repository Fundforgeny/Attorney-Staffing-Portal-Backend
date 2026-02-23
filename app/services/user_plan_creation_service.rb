# app/services/user_plan_creation_service.rb
class UserPlanCreationService
  def initialize(user_params, plan_params)
    @user_params = user_params
    @plan_params = plan_params
  end

  def create_user_and_plan
    ActiveRecord::Base.transaction do
      user = create_or_find_user
      plan = create_plan_instance(user)
      { user: user, plan: plan }
    end
  end

  private

  def create_or_find_user
    full_name = @user_params[:name]
    email = @user_params[:email]

    first_name, last_name = User.new.split_name(full_name)
    user = User.find_or_initialize_by(email: email)

    if user.new_record?
      user.first_name = first_name
      user.last_name  = last_name
      user.user_type  = "client"
      user.skip_confirmation!    
    end

    user.save!
    user
  end

  def create_plan_instance(user)
    plan = if @plan_params[:plan_id].present?
             Plan.find_by(id: @plan_params[:plan_id])
           else
             Plan.find_or_initialize_by(user: user, name: @plan_params[:name])
           end

    raise ActiveRecord::RecordNotFound, "Plan not found" if @plan_params[:plan_id].present? && plan.nil?

    duration = @plan_params[:duration].to_i
    selected_payment_plan = PaymentPlanFeeCalculator.plan_selected?(
      selected_payment_plan: @plan_params[:selected_payment_plan],
      duration: duration
    )
    base_legal_fee = @plan_params[:total_payment].to_d
    fee_calculator = PaymentPlanFeeCalculator.new(
      base_amount: base_legal_fee,
      selected_payment_plan: selected_payment_plan
    )
    administration_fee = fee_calculator.fee_amount

    plan.assign_attributes(
      name: @plan_params[:name],
      duration: duration,
      total_payment: base_legal_fee,
      total_interest_amount: administration_fee,
      monthly_payment: @plan_params[:monthly_payment],
      monthly_interest_amount: duration.positive? ? (administration_fee / duration).round(2) : 0,
      down_payment: @plan_params[:down_payment],
      status: :active
    )

    plan.save!
    plan
  end
end
