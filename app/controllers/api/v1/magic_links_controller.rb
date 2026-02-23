class Api::V1::MagicLinksController < ActionController::API
  include ApiResponse

  def create_user_with_magic_link
    # Validate required parameters
    required_params = [:name, :email, :id, :retainer_amount, :down_payment, :location_id]
    missing_params = required_params.select { |param| params[param].blank? }
    
    unless missing_params.empty?
      return render_error(
        message: "Missing required parameters: #{missing_params.join(', ')}", 
        status: :bad_request
      )
    end

    ActiveRecord::Base.transaction do
      full_name = params[:name].to_s.strip
      first_name, last_name = full_name.split(" ", 2)

      user = User.find_or_initialize_by(email: params[:email])

      user.assign_attributes(
        first_name: first_name,
        last_name: last_name || "",
        phone: params[:phone]
      )
      
      # Find firm by location_id
      firm = Firm.find_by(location_id: params[:location_id])
      unless firm
        return render_error(
          message: "Firm not found for location_id: #{params[:location_id]}", 
          status: :not_found
        )
      end
      
      # Skip confirmation for API-created users
      retainer_amount = params[:retainer_amount].to_s.gsub(/[$,]/, '').to_f
      down_payment    = params[:down_payment].to_s.gsub(/[$,]/, '').to_f

      user.skip_confirmation!
      user.save!

      # Create or update firm_user association with GHL ID
      firm_user = FirmUser.find_or_initialize_by(user: user, firm: firm)
      firm_user.assign_attributes(
        ghl_fund_forge_id: params[:id]
      )
      firm_user.save!

      plan = Plan.where(user_id: user.id, name: "temp_plan").where.not(magic_link_token: [nil, ""])

      if plan.exists?
        plan = plan.last
        magic_link_token = plan.magic_link_token
      else
        magic_link_token = generate_magic_link_token(user)

        plan = Plan.create!(
          user: user,
          name: "temp_plan",
          total_payment: retainer_amount,
          down_payment: down_payment,
          monthly_payment: 0,
          status: :active,
          magic_link_token: magic_link_token
        )
      end

      frontend_url = "https://payments.fundforge.net/pay"
      magic_link = "#{frontend_url}?token=#{magic_link_token}"

      render_success(
        data: {
          user_id: user.id,
          email: user.email,
          plan_id: plan.id,
          magic_link: magic_link,
          firm_id: firm.id,
          firm_name: firm.name
        },
        message: "User and plan created successfully with magic link",
        status: :created
      )
      return
    end
  rescue ActiveRecord::RecordInvalid => e
    render_error(message: e.record.errors.full_messages.join(", "), status: :unprocessable_entity)
    return
  rescue StandardError => e
    render_error(message: e.message, status: :unprocessable_entity)
    return
  end

  def validate
    token = params[:token]
    return render_error(message: "Token and user_id are required", status: :bad_request) if token.blank?

    plan = Plan.find_by(magic_link_token: token)
    return render_error(message: "Plan not found", status: :bad_request) if plan.blank?

    user = User.find_by(id: plan.user_id)
    return render_error(message: "User not found", status: :not_found) if user.blank?

    render_success(
      data: {
        user_id: user.id,
        name: user.first_name + " " + user.last_name,
        email: user.email,
        plan_id: plan.id,
        down_payment: plan.down_payment.to_i,
        base_legal_fee: plan.base_legal_fee_amount.to_f,
        administration_fee_name: plan.administration_fee_name,
        administration_fee_percentage: plan.administration_fee_percentage,
        administration_fee_amount: plan.administration_fee_amount.to_f,
        total_payment_plan_amount: plan.total_payment_plan_amount.to_f,
        payment_plan_selected: plan.payment_plan_selected?,
        checkout_disclosure: "Clients who elect to enroll in a Fund Forge managed payment plan agree to a 4% Payment Plan Administration Fee. This fee applies to all installment plans regardless of payment method. Clients who pay in full via cash, check, or wire at the time of engagement do not incur this fee.",
        status: plan.status
      },
      message: "Magic link validated successfully",
      status: :ok
    )
  end

  private

  def generate_magic_link_token(user)
    token = SecureRandom.urlsafe_base64(32)
    token
  end
end
