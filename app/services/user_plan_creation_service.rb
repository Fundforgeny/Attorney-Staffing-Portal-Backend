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
    if @plan_params[:plan_id].present?
      plan = Plan.find_by(id: @plan_params[:plan_id])
      raise ActiveRecord::RecordNotFound, "Plan not found" if plan.nil?
      
      plan.update!(
        name: @plan_params[:name],
        duration: @plan_params[:duration],
        total_payment: @plan_params[:total_payment],
        total_interest_amount: @plan_params[:total_interest],
        monthly_payment: @plan_params[:monthly_payment],
        monthly_interest_amount: @plan_params[:monthly_interest],
        down_payment: @plan_params[:down_payment],
        status: :active
      )
    else
      plan = Plan.create!(
        user: user,
        name: @plan_params[:name],
        duration: @plan_params[:duration],
        total_payment: @plan_params[:total_payment],
        total_interest_amount: @plan_params[:total_interest],
        monthly_payment: @plan_params[:monthly_payment],
        monthly_interest_amount: @plan_params[:monthly_interest],
        down_payment: @plan_params[:down_payment],
        status: :active
      )
    end
    
    plan
  end
end
