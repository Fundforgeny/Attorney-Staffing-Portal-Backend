# app/controllers/api/v1/payments_controller.rb
class Api::V1::PaymentsController < ActionController::API
  include ApiResponse
  include SpreedlyCallbackUrl

  before_action :set_user_params, only: [:create_user_plan]
  before_action :set_checkout_params, only: [:checkout]
  before_action :set_payment_params, only: [:process_payment]
  before_action :set_signature_params, only: [:save_signature]

  def create_user_plan
    agreement = nil

    ActiveRecord::Base.transaction do
      result = UserPlanCreationService.new(@user_params, @plan_params).create_user_and_plan
      user = result[:user]
      plan = result[:plan]

      agreement = Agreement.create!(user: user, plan: plan)
    end

    # Attach PDFs outside the transaction; never raise on failure
    begin
      AgreementAttachmentService.new(agreement).attach_agreements if agreement
    rescue StandardError => e
      Rails.logger.error("PDF attachment failed for Agreement ##{agreement&.id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if Rails.env.development?
    end

    agreement&.reload

    render_success(
      data: build_agreement_response(agreement),
      message: "User and plan created successfully with agreements",
      status: :created
    )
  rescue StandardError => e
    Rails.logger.error("Error in create_user_plan: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if Rails.env.development?
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def iframe_security
    render_success(data: Spreedly::IframeSecurityService.payload, status: :ok)
  rescue StandardError => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def checkout
    ActiveRecord::Base.transaction do
      user = User.find(@checkout_params[:user_id])
      plan = Plan.find(@checkout_params[:plan_id])
      if plan.user != user
        return render_error(message: "Plan does not belong to user", status: :unprocessable_entity)
      end
      render_error(message: "Plan is already paid", status: :unprocessable_entity) and return if plan.paid?
      render_error(message: "Plan is expired", status: :unprocessable_entity) and return if plan.expired?

      PaymentService.new(user, plan, @checkout_params, @checkout_params[:first_installment_date]).process_checkout
      plan.update!(status: :payment_pending) unless plan.paid?
      
      render_success(
        data: {user_id: user.id, plan_id: plan.id},
        message: "Checkout completed successfully",
        status: :created
      )
    end
  rescue StandardError => e
    render_error(message: e.message)
  end

  def process_payment
    @user = User.find(@payment_params[:user_id])
    @plan = Plan.find(@payment_params[:plan_id])
    unless @plan.user_id == @user.id
      return render_error(message: "Plan does not belong to user", status: :unprocessable_entity)
    end

    # Backward-compatible behavior:
    # - when require_3ds is false/missing => existing direct process_payment path
    # - when require_3ds is true => initiate 3DS challenge or complete an existing 3DS session
    if require_three_ds?
      return complete_three_ds_payment! if @payment_params[:three_ds_session_id].present?
      return start_three_ds_payment!
    end

    result = SpreedlyService.new(@user, @plan, @payment_params).process_payment

    if result[:success]
      @plan.update!(status: :paid) if result.dig(:data, :payment_type).to_s == "full_payment"
      render_success(data: result[:data], message: "Payment processed successfully", status: :ok)
    else
      @plan.update!(status: :failed) unless @plan.paid?
      render_error(message: result[:error], status: result[:status] || :unprocessable_entity)
    end
  rescue StandardError => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  # Below API's are deprecated
  # **************************
  # def create_verification_session
  #   user = User.find_by(id: params[:user_id])
  #   unless user
  #     return render_error(message: "User not found", status: :not_found)
  #   end

  #   begin
  #     verification_session = Stripe::Identity::VerificationSession.create(
  #       type: 'document'
  #     )
  #     # Save the record in DB
  #     user.update!(stripe_verification_session_id: verification_session.id)

  #     render_success(
  #       data: {
  #         client_secret: verification_session.client_secret
  #       },
  #       message: "Verification session created successfully",
  #       status: :created
  #     )

  #   rescue Stripe::StripeError => e
  #     render_error(message: e.message)
  #   end
  # end

  # def create_payment_session
  #   begin
  #     required_params = [:user_id, :plan_id]
  #     missing_params = required_params.select { |param| params[param].blank? }
  #     render_error("Missing parameters: #{missing_params.join(', ')}") unless missing_params.empty?

  #     user = User.find(params[:user_id])
  #     plan = Plan.find(params[:plan_id])

  #     render_error("Plan does not belong to user") unless plan.user_id == user.id

  #     if user.stripe_customer_id.present?
  #       begin
  #         Stripe::Customer.retrieve(user.stripe_customer_id)
  #       rescue Stripe::InvalidRequestError => e
  #         if e.message.include?("No such customer")
  #           create_new_stripe_customer(user)
  #         else
  #           raise e
  #         end
  #       end
  #     else
  #       create_new_stripe_customer(user)
  #     end

  #     payment_type = plan&.duration > 0 ? "down_payment" : "full_payment"
  #     payment = Payment.find_by(user: user, plan: plan, payment_type: payment_type)

  #     render_error("Payment not found") unless payment && payment.total_payment_including_fee.present?

  #     intent_data = {
  #       amount: (payment.total_payment_including_fee * 100).to_i,
  #       currency: 'usd',
  #       customer: user.stripe_customer_id,
  #       description: payment.payment_type,
  #       receipt_email: user.email,
  #       metadata: {
  #         user_id: user.id,
  #         plan_id: plan.id,
  #         payment_type: payment_type
  #       }
  #     }
  #     intent_data[:setup_future_usage] = 'off_session' if payment_type == "down_payment"

  #     intent = Stripe::PaymentIntent.create(intent_data)
  #     payment.update(charge_id: intent.id, status: :processing) if intent

  #     render_success(
  #       data: {
  #         client_secret: intent.client_secret
  #       },
  #       message: "Payment intent created successfully",
  #       status: :created
  #     )

  #   rescue Stripe::StripeError => e
  #     render_error(message: e.message)
  #   rescue ActiveRecord::RecordNotFound => e
  #     render_error(message: "User or plan not found", status: :not_found)
  #   rescue StandardError => e
  #     render_error(message: "Something went wrong: #{e.message}")
  #   end
  # end

  def save_signature
    begin
      result = SignatureService.new(@user, @agreement, @signature_params[:signature]).save_signature
      
      render_success(
        data: result,
        message: "Signature saved successfully",
        status: :created
      )
    rescue ActiveRecord::RecordNotFound => e
      render_error(message: "Record not found: #{e.message}", status: :not_found)
    rescue ArgumentError => e
      render_error(message: e.message, status: :bad_request)
    end
  end

  private

  def set_signature_params
    @signature_params = params.permit(:signature, :user_id, :agreement_id, :checkout_session_id)
    if @signature_params[:signature].blank?
      return render_error(message: "Missing required parameters: signature", status: :bad_request)
    end

    if @signature_params[:agreement_id].present? && @signature_params[:user_id].present?
      @user = User.find(@signature_params[:user_id])
      @agreement = Agreement.find(@signature_params[:agreement_id])
      return
    end

    if @signature_params[:checkout_session_id].present?
      plan = Plan.find_by(checkout_session_id: @signature_params[:checkout_session_id])
      return render_error(message: "Plan not found", status: :not_found) if plan.blank?

      @agreement = plan.agreement
      return render_error(message: "Agreement not found for plan", status: :not_found) if @agreement.blank?

      @user = plan.user
      return
    end

    render_error(
      message: "Missing required parameters: user_id and agreement_id, or checkout_session_id",
      status: :bad_request
    )
  end

  def set_payment_params
    @payment_params = params.permit(
      :user_id,
      :plan_id,
      :vault_token,
      :card_brand,
      :payment_method_id,
      :three_ds_session_id,
      :require_3ds,
      :browser_info
    )
  end

  def set_checkout_params
    @checkout_params = params.permit(
      :user_id,
      :plan_id,
      :first_installment_date,
      :payment_method_id,
      :vault_token,
      :card_brand,
      :last4,
      :exp_month,
      :exp_year,
      :cardholder_name,
      payment_method: [ :number, :cvc, :exp_month, :exp_year, :last_four, :vault_token, :card_brand, :last4, :payment_method_id ]
    )
  end

  def set_user_params
    @user_params = params.require(:user).permit(:name, :email)
    @plan_params = params.require(:plan).permit(
      :checkout_session_id,
      :name,
      :duration,
      :total_payment,
      :total_interest,
      :monthly_payment,
      :monthly_interest,
      :down_payment,
      :plan_id,
      :selected_payment_plan
    )
  end

  def build_agreement_response(agreement)
    plan = agreement.plan
    payment_plan_selected = plan.payment_plan_selected?

    {
      user_id: agreement.user_id,
      plan_id: agreement.plan_id,
      agreement_id: agreement.id,
      order_summary: build_order_summary(plan, payment_plan_selected),
      fund_forge_agreement: agreement.pdf.attached? ? { url: agreement.pdf.url, filename: agreement.pdf.filename.to_s } : nil,
      engagement_agreement: agreement.engagement_pdf.attached? ? { url: agreement.engagement_pdf.url, filename: agreement.engagement_pdf.filename.to_s } : nil
    }.compact
  end

  def build_order_summary(plan, payment_plan_selected)
    if payment_plan_selected
      {
        base_legal_fee: plan.base_legal_fee_amount,
        administration_fee_name: plan.administration_fee_name,
        administration_fee_percentage: plan.administration_fee_percentage,
        administration_fee_amount: plan.administration_fee_amount,
        total_payment_plan_amount: plan.total_payment_plan_amount,
        disclosure: "Clients who elect to enroll in a Fund Forge managed payment plan agree to a 4% Payment Plan Administration Fee. This fee applies to all installment plans regardless of payment method. Clients who pay in full via cash, check, or wire at the time of engagement do not incur this fee."
      }
    else
      {
        base_legal_fee: plan.base_legal_fee_amount,
        total_due: plan.base_legal_fee_amount
      }
    end
  end

  # Not being used now
  # ******************
  # def create_new_stripe_customer(user)
  #   customer = Stripe::Customer.create({
  #     email: user.email,
  #     name: user.full_name,
  #     metadata: { user_id: user.id }
  #   })
  #   user.update!(stripe_customer_id: customer.id)
  # end

  def require_three_ds?
    ActiveModel::Type::Boolean.new.cast(@payment_params[:require_3ds])
  end

  def start_three_ds_payment!
    if sca_provider_key.present? && @payment_params[:browser_info].blank?
      return render_error(message: "browser_info is required for 3DS2 authentication", status: :unprocessable_entity)
    end

    payment_method = resolve_payment_method_for_three_ds!
    payment = resolve_payment_for_three_ds!
    payment.update!(payment_method: payment_method) if payment.payment_method_id != payment_method.id

    callback_token = SecureRandom.hex(24)
    callback_url = spreedly_three_ds_callback_url(callback_token)
    redirect_url = spreedly_three_ds_redirect_url

    raw_transaction = Spreedly::ThreeDsService.new.initiate_purchase(
      payment_method_token: payment_method.vault_token,
      amount_cents: (payment.total_payment_including_fee.to_d * 100).to_i,
      currency: "USD",
      callback_url: callback_url,
      redirect_url: redirect_url,
      workflow_key: composer_workflow_key,
      browser_info: @payment_params[:browser_info],
      sca_provider_key: sca_provider_key,
      ip: request.remote_ip
    )
    transaction = normalize_transaction(raw_transaction)
    if transaction.blank?
      return render_error(message: "Invalid 3DS response from Spreedly", status: :unprocessable_entity)
    end

    challenge_url = Spreedly::ThreeDsService.new.extract_challenge_url(transaction)
    session_status = derive_three_ds_session_status(transaction["state"], challenge_url)
    session = Payment3dsSession.create!(
      user: @user,
      plan: @plan,
      payment: payment,
      payment_method: payment_method,
      status: session_status,
      callback_token: callback_token,
      spreedly_transaction_token: transaction["token"],
      challenge_url: challenge_url,
      raw_response: transaction
    )

    if three_ds_terminal_state?(transaction["state"])
      apply_three_ds_transaction_result!(payment, @plan, transaction)
      return render_terminal_three_ds_response!(session, payment, transaction)
    end

    render_success(
      data: {
        status: "action_required",
        three_ds_required: true,
        three_ds_session_id: session.id,
        challenge_url: challenge_url,
        transaction_token: transaction["token"],
        expires_at: 15.minutes.from_now.iso8601
      },
      message: "3DS verification required",
      status: :ok
    )
  end

  def complete_three_ds_payment!
    session = Payment3dsSession.find_by(id: @payment_params[:three_ds_session_id], user_id: @user.id, plan_id: @plan.id)
    return render_error(message: "3DS session not found", status: :not_found) if session.blank?

    raw_transaction = Spreedly::ThreeDsService.new.fetch_transaction(transaction_token: session.spreedly_transaction_token)
    transaction = normalize_transaction(raw_transaction)
    if transaction.blank?
      return render_error(message: "Invalid 3DS transaction status response", status: :unprocessable_entity)
    end
    session_status = derive_three_ds_session_status(transaction["state"], session.challenge_url)
    session.update!(
      raw_response: transaction,
      status: session_status,
      completed_at: three_ds_terminal_state?(transaction["state"]) ? Time.current : nil
    )

    unless three_ds_terminal_state?(transaction["state"])
      return render_success(
        data: {
          status: session.status,
          three_ds_required: true,
          three_ds_session_id: session.id,
          challenge_url: session.challenge_url,
          transaction_token: session.spreedly_transaction_token
        },
        message: "3DS verification still in progress",
        status: :ok
      )
    end

    apply_three_ds_transaction_result!(session.payment, session.plan, transaction)
    render_terminal_three_ds_response!(session, session.payment, transaction)
  end

  def resolve_payment_method_for_three_ds!
    if @payment_params[:payment_method_id].present?
      return @user.payment_methods.find(@payment_params[:payment_method_id])
    end

    if @payment_params[:vault_token].present?
      payment_method = @user.payment_methods.new(
        vault_token: @payment_params[:vault_token],
        provider: "Spreedly Vault",
        card_brand: @payment_params[:card_brand],
        last_updated_via_spreedly_at: Time.current,
        is_default: @user.payment_methods.blank?
      )
      payment_method.save!
      return payment_method
    end

    default_payment_method = @user.payment_methods.ordered_for_user.first
    return default_payment_method if default_payment_method.present?

    raise ArgumentError, "Missing payment method: provide payment_method_id or vault_token"
  end

  def resolve_payment_for_three_ds!
    payment_type = @plan.duration.to_i > 0 ? "down_payment" : "full_payment"
    payment = Payment.find_by(user: @user, plan: @plan, payment_type: payment_type)
    raise ArgumentError, "Payment not found" if payment.blank? || payment.total_payment_including_fee.blank?

    payment
  end

  def derive_three_ds_session_status(state, challenge_url)
    return "succeeded" if state.to_s == "succeeded"
    return "failed" if %w[failed gateway_processing_failed scrubbed].include?(state.to_s)
    return "challenged" if challenge_url.present?

    "pending"
  end

  def three_ds_terminal_state?(state)
    Spreedly::ThreeDsService.new.terminal_state?(state)
  end

  def apply_three_ds_transaction_result!(payment, plan, transaction)
    tx = normalize_transaction(transaction)
    succeeded = ActiveModel::Type::Boolean.new.cast(tx["succeeded"]) || tx["state"].to_s == "succeeded"

    payment.update!(
      charge_id: tx["token"] || payment.charge_id,
      status: succeeded ? :succeeded : :failed,
      paid_at: succeeded ? Time.current : nil
    )
    plan.update!(status: :paid) if succeeded && payment.payment_type.to_s == "full_payment"
    plan.update!(status: :failed) unless succeeded || plan.paid?
  end

  def render_terminal_three_ds_response!(session, payment, transaction)
    tx = normalize_transaction(transaction)
    succeeded = ActiveModel::Type::Boolean.new.cast(tx["succeeded"]) || tx["state"].to_s == "succeeded"
    payload = {
      status: succeeded ? "succeeded" : "failed",
      three_ds_required: true,
      three_ds_session_id: session.id,
      transaction_token: tx["token"] || session.spreedly_transaction_token,
      state: tx["state"],
      payment_type: payment.payment_type
    }

    if succeeded
      render_success(data: payload, message: "Payment processed successfully", status: :ok)
    else
      render_error(message: "Payment failed: #{tx['message'].presence || '3DS authentication failed'}", status: :payment_required)
    end
  end

  def normalize_transaction(transaction)
    return transaction if transaction.is_a?(Hash)

    {}
  end

  def composer_workflow_key
    ENV["SPREEDLY_WORKFLOW_KEY"].presence || ENV["SPREEDLY_COMPOSER_WORKFLOW_KEY"].presence
  end

  def sca_provider_key
    ENV["SPREEDLY_SCA_PROVIDER_KEY"].presence
  end
end
