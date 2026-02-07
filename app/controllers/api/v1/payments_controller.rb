# app/controllers/api/v1/payments_controller.rb
class Api::V1::PaymentsController < ActionController::API
  include ApiResponse

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

  def checkout
    ActiveRecord::Base.transaction do
      user = User.find(@checkout_params[:user_id])
      plan = Plan.find(@checkout_params[:plan_id])
      render_error("Plan does not belong to user") if plan.user != user

      PaymentService.new(user, plan, @checkout_params[:payment_method], @checkout_params[:first_installment_date]).process_checkout
      
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
    render_error("Plan does not belong to user") unless @plan.user_id == @user.id
    result = SpreedlyService.new(@user, @plan, @payment_params).process_payment
    
    if result[:success]
      render_success(data: result[:data], message: "Payment processed successfully", status: :ok)
    else
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
    required_params = [:user_id, :agreement_id, :signature]
    missing_params = required_params.select { |param| params[param].blank? }
    render_error("Missing required parameters: #{missing_params.join(', ')}") unless missing_params.empty?

    @user = User.find(params[:user_id])
    @agreement = Agreement.find(params[:agreement_id])
    @signature_params = params.permit(:signature)
  end

  def set_payment_params
    @payment_params = params.permit(:user_id, :plan_id, :vault_token, :card_brand)
  end

  def set_checkout_params
    @checkout_params = params.permit(:user_id, :plan_id, :first_installment_date, payment_method: [:number, :cvc, :exp_month, :exp_year, :last_four])
  end

  def set_user_params
    @user_params = params.require(:user).permit(:name, :email)
    @plan_params = params.require(:plan).permit(:name, :duration, :total_payment, :total_interest, :monthly_payment, :monthly_interest, :down_payment, :plan_id)
  end

  def build_agreement_response(agreement)
    {
      user_id: agreement.user_id,
      plan_id: agreement.plan_id,
      agreement_id: agreement.id,
      fund_forge_agreement: agreement.pdf.attached? ? { url: agreement.pdf.url, filename: agreement.pdf.filename.to_s } : nil,
      engagement_agreement: agreement.engagement_pdf.attached? ? { url: agreement.engagement_pdf.url, filename: agreement.engagement_pdf.filename.to_s } : nil
    }.compact
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
end
