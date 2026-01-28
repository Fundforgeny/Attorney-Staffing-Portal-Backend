# app/services/magic_link_service.rb
class MagicLinkService
  def initialize(user_params, plan_params)
    @user_params = user_params
    @plan_params = plan_params
  end

  def create_user_and_magic_link
    ActiveRecord::Base.transaction do
      user = create_or_find_user
      firm = find_firm
      associate_user_with_firm(user, firm)
      plan = create_temp_plan(user)
      
      {
        user: user,
        plan: plan,
        firm: firm,
        magic_link: generate_magic_link_url(plan)
      }
    end
  end

  private

  def create_or_find_user
    user = User.find_or_initialize_by(email: @user_params[:email])
    
    if user.new_record? || user.changed?
      first_name, last_name = User.new.split_name(@user_params[:name])
      user.assign_attributes(
        first_name: first_name,
        last_name: last_name,
        phone: @user_params[:phone]
      )
      user.skip_confirmation!
      user.save!
    end
    
    user
  end

  def find_firm
    firm = Firm.find_by(location_id: @plan_params[:location_id])
    raise ArgumentError, "Firm not found for location_id: #{@plan_params[:location_id]}" if firm.blank?
    firm
  end

  def associate_user_with_firm(user, firm)
    return unless firm
    
    firm_user = FirmUser.find_or_initialize_by(user: user, firm: firm)
    firm_user.assign_attributes(ghl_fund_forge_id: @plan_params[:id]) if @plan_params[:id].present?
    firm_user.save!
  end

  def create_temp_plan(user)
    plan = Plan.find_or_initialize_by(user_id: user.id, name: "temp_plan")
    
    plan.assign_attributes(
      total_payment: Plan.parse_amount(@plan_params[:retainer_amount]),
      down_payment: Plan.parse_amount(@plan_params[:down_payment]),
      monthly_payment: 0,
      status: :active
    )

    plan.magic_link_token = generate_magic_link_token(user) if plan.magic_link_token.blank?
    plan.save!
    
    plan
  end

  def generate_magic_link_token(user)
    token = SecureRandom.urlsafe_base64(32)
    token
  end

  def generate_magic_link_url(plan)
    frontend_url = "https://payments.fundforge.net/pay"
    "#{frontend_url}?token=#{plan.magic_link_token}"
  end
end
