class Api::V1::MagicLinksController < ActionController::API
  include ApiResponse

  def create_user_with_magic_link
    # Only name, email, and location_id are strictly required.
    # retainer_amount, down_payment, and id may be blank when GHL custom
    # fields haven't been filled in yet — they default to 0 / empty string.
    required_params = [:name, :email, :location_id]
    missing_params = required_params.select { |param| params[param].blank? }

    unless missing_params.empty?
      return render_error(
        message: "Missing required parameters: #{missing_params.join(', ')}",
        status: :bad_request
      )
    end

    ActiveRecord::Base.transaction do
      full_name  = params[:name].to_s.strip
      first_name, last_name = full_name.split(" ", 2)

      normalized_email = params[:email].to_s.strip.downcase
      normalized_phone = params[:phone].to_s.gsub(/\D/, '')

      # ── 1. Find or build user (never create duplicates) ──────────────────
      user = User.find_by(email: normalized_email)
      user ||= User.find_by(phone: normalized_phone) if normalized_phone.present?

      if user
        # Update existing user's contact details with the latest data from GHL
        user.assign_attributes(
          first_name: first_name,
          last_name:  last_name || "",
          phone:      normalized_phone.presence || user.phone,
          email:      normalized_email
        )
        user.skip_confirmation!
        user.save!
      else
        # New user — Devise requires a password; generate a secure random one
        # (clients authenticate via magic link, not password)
        user = User.new(
          email:      normalized_email,
          first_name: first_name,
          last_name:  last_name || "",
          phone:      normalized_phone.presence,
          password:   SecureRandom.hex(16),
          user_type:  :client
        )
        user.skip_confirmation!
        user.save!
      end

      # ── 2. Find firm by location_id ───────────────────────────────────────
      firm = Firm.find_by(location_id: params[:location_id])
      unless firm
        return render_error(
          message: "Firm not found for location_id: #{params[:location_id]}",
          status: :not_found
        )
      end

      retainer_amount = params[:retainer_amount].to_s.gsub(/[$,]/, '').to_f
      down_payment    = params[:down_payment].to_s.gsub(/[$,]/, '').to_f

      # ── 3. Create or update firm_user association with GHL contact ID ─────
      firm_user = FirmUser.find_or_initialize_by(user: user, firm: firm)
      firm_user.assign_attributes(ghl_fund_forge_id: params[:id])
      firm_user.save!

      # ── 4. Always generate a FRESH magic link token ───────────────────────
      # This guarantees a working link on every webhook call regardless of
      # whether the user or their plan already existed.
      magic_link_token    = SecureRandom.urlsafe_base64(32)
      checkout_session_id = magic_link_token

      # ── 5. Upsert the draft plan ──────────────────────────────────────────
      # Find the most recent draft/temp plan for this user (if any) and update
      # it in-place so we never accumulate stale plans.  If none exists, create
      # a new one.
      plan = Plan.where(user_id: user.id, name: "temp_plan")
                 .where(status: Plan.statuses[:draft])
                 .order(created_at: :desc)
                 .first

      if plan
        # Update existing draft plan with fresh token + new amounts
        plan.update!(
          total_payment:      retainer_amount,
          down_payment:       down_payment,
          monthly_payment:    0,
          magic_link_token:   magic_link_token,
          checkout_session_id: checkout_session_id,
          status:             :draft
        )
      else
        plan = Plan.create!(
          user:               user,
          name:               "temp_plan",
          total_payment:      retainer_amount,
          down_payment:       down_payment,
          monthly_payment:    0,
          status:             :draft,
          magic_link_token:   magic_link_token,
          checkout_session_id: checkout_session_id
        )
      end

      frontend_url = "https://payments.fundforge.net/pay"
      magic_link   = "#{frontend_url}?token=#{magic_link_token}"

      render_success(
        data: {
          user_id:   user.id,
          email:     user.email,
          plan_id:   plan.id,
          magic_link: magic_link,
          firm_id:   firm.id,
          firm_name: firm.name
        },
        message: "User and plan created successfully with magic link",
        status: :created
      )
    end
  rescue ActiveRecord::RecordInvalid => e
    render_error(message: e.record.errors.full_messages.join(", "), status: :unprocessable_entity)
  rescue ActiveRecord::RecordNotUnique => e
    render_error(message: "Duplicate record conflict: #{e.message}", status: :unprocessable_entity)
  rescue StandardError => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def validate
    token = params[:token]
    return render_error(message: "Token and user_id are required", status: :bad_request) if token.blank?

    plan = Plan.find_by(magic_link_token: token)
    return render_error(message: "Plan not found", status: :bad_request) if plan.blank?

    # Backfill legacy records created with "magic-link-<token>" so resume API
    # can use the same token value as checkout_session_id.
    if plan.checkout_session_id.present? && plan.checkout_session_id != token
      begin
        plan.update!(checkout_session_id: token)
      rescue ActiveRecord::RecordNotUnique
        # Keep existing session id if another row already owns token as checkout id.
      end
    end

    user = User.find_by(id: plan.user_id)
    return render_error(message: "User not found", status: :not_found) if user.blank?

    render_success(
      data: {
        user_id:                    user.id,
        name:                       user.full_name,
        email:                      user.email,
        phone:                      user.phone,
        billing_address1:           user.address_street,
        billing_city:               user.city,
        billing_state:              user.state,
        billing_zip:                user.postal_code,
        billing_country:            user.country.presence || "United States",
        plan_id:                    plan.id,
        checkout_session_id:        plan.checkout_session_id,
        token:                      token,
        total_amount:               plan.total_payment.to_f,
        total_payment:              plan.total_payment.to_f,
        down_payment:               plan.down_payment.to_i,
        base_legal_fee:             plan.base_legal_fee_amount.to_f,
        administration_fee_name:    plan.administration_fee_name,
        administration_fee_percentage: plan.administration_fee_percentage,
        administration_fee_amount:  plan.administration_fee_amount.to_f,
        total_payment_plan_amount:  plan.total_payment_plan_amount.to_f,
        payment_plan_selected:      plan.payment_plan_selected?,
        checkout_disclosure:        "Clients who elect to enroll in a Fund Forge managed payment plan agree to a 4% Payment Plan Administration Fee. This fee applies to all installment plans regardless of payment method. Clients who pay in full via cash, check, or wire at the time of engagement do not incur this fee.",
        status:                     plan.status
      },
      message: "Magic link validated successfully",
      status: :ok
    )
  end

  private

  def generate_magic_link_token(_user)
    SecureRandom.urlsafe_base64(32)
  end
end
