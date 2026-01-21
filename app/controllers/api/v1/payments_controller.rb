# app/controllers/api/v1/payments_controller.rb
class Api::V1::PaymentsController < ActionController::API
  include ApiResponse

  def create_user_plan
    ActiveRecord::Base.transaction do
      user = create_or_find_user
      plan = create_plan_instance(user)

      # Generate the filled agreement PDF (returns a file path)
      fund_forge_pdf_path = AgreementPdfGenerator.new(user, plan).generate
      fund_forge_filename = "fund_forge_agreement_#{plan.id}.pdf"

      engagement_pdf_path = EngagementPdfGenerator.new(user, plan).generate
      engagement_filename = "engagement_agreement_#{plan.id}.pdf"

      agreement = Agreement.create(user: user, plan: plan)

      agreement.pdf.attach(
        io: File.open(fund_forge_pdf_path),
        filename: fund_forge_filename,
        content_type: "application/pdf"
      )

      agreement.engagement_pdf.attach(
        io: File.open(engagement_pdf_path),
        filename: engagement_filename,
        content_type: "application/pdf"
      )
      
      # Generate S3 public URL
      fund_forge_agreement_url = agreement.pdf.url
      engagement_agreement_url = agreement.engagement_pdf.url

      render_success(
        data: {
          user_id: user.id,
          plan_id: plan.id,
          agreement_id: agreement.id,
          fund_forge_agreement: {
          url: fund_forge_agreement_url,
          filename: fund_forge_filename,
          },
          engagement_agreement: {
          url: engagement_agreement_url,
          filename: engagement_filename,
          },
        },
        message: "User and plan created successfully with signed agreement",
        status: :created
      )
    end
  rescue StandardError => e
    render_error(message: e.message, status: :unprocessable_entity)
  end

  def checkout
    ActiveRecord::Base.transaction do
      user = User.find(params[:user_id])
      plan = Plan.find(params[:plan_id])
      raise ArgumentError, "Plan does not belong to user" if plan.user != user

      payment_method = store_vault_token(user)
      payments = create_payment_schedule(plan, payment_method)

      # result = StripePaymentService.new(payments)
      # result = SquarePaymentService.new(payments)

      render_success(
        data: {
          user_id: user.id,
          plan_id: plan.id,
          payments: payments.map { |p| payment_serializer(p) }
        },
        message: "Checkout completed successfully",
        status: :created
      )
    end
  rescue StandardError => e
    render_error(message: e.message)
  end

  def create_verification_session
    user = User.find_by(id: params[:user_id])
    unless user
      return render_error(message: "User not found", status: :not_found)
    end

    begin
      verification_session = Stripe::Identity::VerificationSession.create(
        type: 'document'
      )
      # Save the record in DB
      user.update!(stripe_verification_session_id: verification_session.id)

      render_success(
        data: {
          client_secret: verification_session.client_secret
        },
        message: "Verification session created successfully",
        status: :created
      )

    rescue Stripe::StripeError => e
      render_error(message: e.message)
    end
  end

  def create_payment_session
    begin
      required_params = [:user_id, :plan_id]
      missing_params = required_params.select { |param| params[param].blank? }
      unless missing_params.empty?
        return render_error(message: "Missing parameters: #{missing_params.join(', ')}", status: :bad_request)
      end

      user = User.find(params[:user_id])
      plan = Plan.find(params[:plan_id])

      unless plan.user_id == user.id
        return render_error(message: "Plan does not belong to user", status: :forbidden)
      end

      if user.stripe_customer_id.present?
        begin
          Stripe::Customer.retrieve(user.stripe_customer_id)
        rescue Stripe::InvalidRequestError => e
          if e.message.include?("No such customer")
            create_new_stripe_customer(user)
          else
            raise e
          end
        end
      else
        create_new_stripe_customer(user)
      end

      puts "User found with id: #{user.id}"
      puts "Plan found with id: #{plan.id}"

      payment_type = plan&.duration > 0 ? "down_payment" : "full_payment"
      payment = Payment.find_by(user: user, plan: plan, payment_type: payment_type)
      puts "Payment record: #{payment.id} and plan_type: #{payment.payment_type} and amount: #{payment.total_payment_including_fee}"

      unless payment && payment.total_payment_including_fee.present?
        return render_error(message: "Payment not found", status: :not_found)
      end

      intent_data = {
        amount: (payment.total_payment_including_fee * 100).to_i,
        currency: 'usd',
        customer: user.stripe_customer_id,
        description: payment.payment_type,
        receipt_email: user.email,
        metadata: {
          user_id: user.id,
          plan_id: plan.id,
          payment_type: payment_type
        }
      }
      intent_data[:setup_future_usage] = 'off_session' if payment_type == "down_payment"

      intent = Stripe::PaymentIntent.create(intent_data)
      payment.update(charge_id: intent.id, status: :processing) if intent

      render_success(
        data: {
          client_secret: intent.client_secret
        },
        message: "Payment intent created successfully",
        status: :created
      )

    rescue Stripe::StripeError => e
      render_error(message: e.message)
    rescue ActiveRecord::RecordNotFound => e
      render_error(message: "User or plan not found", status: :not_found)
    rescue StandardError => e
      render_error(message: "Something went wrong: #{e.message}")
    end
  end


  require "base64"
  require "stringio"
  def save_signature
    begin
      # Validate required parameters
      required_params = [:user_id, :agreement_id, :signature]
      missing_params = required_params.select { |param| params[param].blank? }
      unless missing_params.empty?
        return render_error(message: "Missing required parameters: #{missing_params.join(', ')}", status: :bad_request)
      end

      # Find the agreement and verify ownership
      agreement = Agreement.find(params[:agreement_id])
      user = User.find(params[:user_id])
      
      # Verify the agreement belongs to the user
      unless agreement.plan.user_id == user.id
        return render_error(message: "Agreement does not belong to user", status: :forbidden)
      end

      # Decode base64 signature
      signature_data = params[:signature]
      unless signature_data.is_a?(String) && signature_data.start_with?('data:image/png;base64,')
        return render_error(message: "Invalid signature format. Expected base64 encoded PNG", status: :bad_request)
      end

      # Extract base64 data
      base64_data = signature_data.sub(/^data:image\/png;base64,/, '')
      
      # Decode and create temporary file
      begin
        decoded_data = Base64.strict_decode64(base64_data)
        
        # Create temporary file
        temp_file = Tempfile.new(['signature_', '.png'])
        temp_file.binmode
        temp_file.write(decoded_data)
        temp_file.rewind
        
        # Attach signature to agreement
        filename = "signature_#{agreement.id}_#{Time.current.to_i}.png"
        agreement.signature.attach(
          io: temp_file,
          filename: filename,
          content_type: "image/png"
        )

        # NEW STAMPING LOGIC
        pdf_coordinates = {
        "pdf" => [130, 430],
        "engagement_pdf" => [130, 670]
        }
        ::ProcessSignedAgreementWorker.perform_async(
          agreement.id, 
          agreement.signature.blob.id, 
          pdf_coordinates
        )
        
        # Update agreement status if needed
        agreement.update!(signed_at: Time.current) if agreement.signed_at.blank?
        
        # Generate signature URL
        signature_url = Rails.application.routes.url_helpers.rails_blob_url(agreement.signature, only_path: true)
        
        render_success(
          data: {
            agreement_id: agreement.id,
            signature_url: signature_url,
            signature_filename: filename,
            signed_at: agreement.signed_at
          },
          message: "Signature saved successfully",
          status: :created
        )
          
      ensure
        # Clean up temporary file
        temp_file&.close
        temp_file&.unlink
      end
      
    rescue ActiveRecord::RecordNotFound => e
      render_error(message: "Record not found: #{e.message}", status: :not_found)
    rescue ArgumentError => e
      render_error(message: e.message, status: :bad_request)
    rescue Base64::DecodeError => e
      render_error(message: "Invalid base64 encoding in signature", status: :bad_request)
    rescue StandardError => e
      Rails.logger.error "Signature save error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render_error(message: "Failed to save signature", status: :internal_server_error)
    end
  end

  private

  def create_or_find_user
    full_name = params.dig(:user, :name)
    email = params.dig(:user, :email)&.downcase&.strip

    if full_name.blank? || email.blank?
      render_error(message: "Name and email are required", status: :bad_request)
      return
    end

    first_name, last_name = full_name.split(" ", 2)
    last_name ||= ""

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

  def store_vault_token(user)
    vault_token = params.dig(:payment_method, :vault_token)
    raise ArgumentError, "vault_token is required" if vault_token.blank?
    PaymentMethod.create!(
      user: user,
      provider: "stripe",
      vault_token: vault_token,
      cardholder_name: "#{user.first_name} #{user.last_name}".strip,
      last4: params.dig(:payment_method, :vault_token)["last_four"].to_s,
      exp_month: params.dig(:payment_method, :vault_token)["exp_month"].to_s,
      exp_year: params.dig(:payment_method, :vault_token)["exp_year"].to_s,
      card_brand: params.dig(:payment_method, :vault_token)["type"]
    )
  end

  def create_plan_instance(user)
    plan_params = params.dig(:plan)

    if plan_params[:plan_id].present?
      plan = Plan.find_by(id: plan_params[:plan_id])
      raise ActiveRecord::RecordNotFound, "Plan not found" if plan.nil?
      
      plan.update!(
        name: plan_params[:name],
        duration: plan_params[:duration],
        total_payment: plan_params[:total_payment],
        total_interest_amount: plan_params[:total_interest],
        monthly_payment: plan_params[:monthly_payment],
        monthly_interest_amount: plan_params[:monthly_interest],
        down_payment: plan_params[:down_payment],
        status: :active
      )
    else
      plan = Plan.create!(
        user: user,
        name: plan_params[:name],
        duration: plan_params[:duration],
        total_payment: plan_params[:total_payment],
        total_interest_amount: plan_params[:total_interest],
        monthly_payment: plan_params[:monthly_payment],
        monthly_interest_amount: plan_params[:monthly_interest],
        down_payment: plan_params[:down_payment],
        status: :active
      )
    end
    
    plan
  end

  def create_payment_schedule(plan, payment_method)
    payments = []
    plan_params = params.dig(:plan)

    # Down payment
    if plan.down_payment > 0
      payments << Payment.create!(
        plan: plan,
        user: plan.user,
        payment_method: payment_method,
        payment_type: plan.duration > 0 ? :down_payment : :full_payment,
        payment_amount: plan.down_payment,
        total_payment_including_fee: (plan.down_payment * 1.03).round(2),
        transaction_fee: (plan.down_payment * 0.03).round(2),
        status: :pending,
        scheduled_at: Time.current
      )
    end

    # Monthly installments
    start_date = params[:first_installment_date].present? ?
                 Time.zone.strptime(params[:first_installment_date], "%m-%d-%Y") :
                 nil

    if plan.duration > 0
      plan.duration.times do |i|
        payments << Payment.create!(
          plan: plan,
          user: plan.user,
          payment_method: payment_method,
          payment_type: :monthly_payment,
          payment_amount: plan.monthly_payment,
          total_payment_including_fee: (plan.monthly_payment * 1.03).round(2),
          transaction_fee: (plan.monthly_payment * 0.03).round(2),
          status: :pending,
          scheduled_at: start_date + i.months
        )
      end
    end
    payments
  end

  def payment_serializer(payment)
    {
      id: payment.id,
      type: payment.payment_type,
      amount: payment.payment_amount,
      status: payment.status,
      scheduled_at: payment.scheduled_at,
      paid_at: payment.paid_at,
      charge_id: payment.charge_id
    }
  end

  def create_new_stripe_customer(user)
    customer = Stripe::Customer.create({
      email: user.email,
      name: user.full_name,
      metadata: { user_id: user.id }
    })
    user.update!(stripe_customer_id: customer.id)
  end
end
