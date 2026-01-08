class Api::V1::MagicLinksController < ActionController::API
  include ApiResponse

  def create_user_with_magic_link
    # Validate required parameters
    required_params = [:name, :email, :id, :retainer_amount, :down_payment]
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

      user = User.find_by(email: params[:email])
      
      if user
        return render_error(message: "User already exists", status: :unprocessable_entity)
      end

      user = User.new(
        email: params[:email],
        ghl_contact_id: params[:id],
        first_name: first_name,
        last_name: last_name || "",
        phone: params[:phone]
      )
      
      # Skip confirmation for API-created users
      user.skip_confirmation!
      user.save!

      plan = Plan.create!(
        user: user,
        name: "temp_plan",
        total_payment: params[:retainer_amount],
        down_payment: params[:down_payment],
        monthly_payment: 0,
        status: :active
      )

      magic_link_token = generate_magic_link_token(user)

      frontend_url = "https://payments.fundforge.net/pay"
      magic_link = "#{frontend_url}?token=#{magic_link_token}"

      render_success(
        data: {
          user_id: user.id,
          email: user.email,
          plan_id: plan.id,
          magic_link: magic_link
        },
        message: "User created successfully with magic link",
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
    user = User.find_by(magic_link_token: token)

    return render_error(message: "Token and user_id are required", status: :bad_request) if token.blank? || user.blank?

    plan = Plan.find_by(user_id: user.id, name: "temp_plan")

    return render_error(message: "User not found", status: :not_found) unless plan

    render_success(
      data: {
        user_id: user.id,
        name: user.first_name + " " + user.last_name,
        email: user.email,
        plan_id: plan.id,
        down_payment: plan.down_payment.to_i,
        total_payment: plan.total_payment.to_i,
        status: plan.status
      },
      message: "Magic link validated successfully",
      status: :ok
    )
  end

  private

  def generate_magic_link_token(user)
    token = SecureRandom.urlsafe_base64(32)

    user.update!(
      magic_link_token: token,
    )

    token
  end
end
