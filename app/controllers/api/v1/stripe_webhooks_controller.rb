class Api::V1::StripeWebhooksController < ActionController::API
  include ApiResponse
  require 'stripe'
  Stripe.api_key = ENV['STRIPE_SECRET_KEY']

  # POST /api/v1/stripe_webhooks
  def receive
    payload = request.raw_post
    sig_header = request.headers['Stripe-Signature']

    begin
      event = Stripe::Webhook.construct_event(
        payload,
        sig_header,
        ENV['STRIPE_WEBHOOK_SECRET']
      )
    rescue JSON::ParserError => e
      Rails.logger.error("Stripe webhook JSON error: #{e.message}")
      return render json: { error: "Invalid payload" }, status: :bad_request
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error("Stripe webhook signature error: #{e.message}")
      return render json: { error: "Invalid signature" }, status: :bad_request
    end

    session = event.data.object
    
    user = User.find_by(stripe_verification_session_id: session.id)
    if user
      user.update!(
        stripe_verification_status: session.status
      )
    end

    render json: { received: true }, status: :ok
  end

  def update_payment_status
    begin
      sig_header = request.env['HTTP_STRIPE_SIGNATURE']
      payload = request.body.read
      endpoint_secret = ENV['STRIPE_PAYMENT_VERIFICATION_WEBHOOK_SECRET']

      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
      payment_intent_events = ['payment_intent.succeeded', 'payment_intent.payment_failed', 'payment_intent.requires_action']

      if payment_intent_events.include?(event.type)
        payment_intent = event.data.object
        payment = Payment.find_by(charge_id: payment_intent.id)

        if payment.nil?
          Rails.logger.warn "Payment record not found for Intent: #{payment_intent.id}"
          return render_success(message: "Intent received but not found in DB")
        end

        case event.type
        when 'payment_intent.succeeded'
          process_success(payment, payment_intent)
          SyncDataToGhl.perform_async(payment.user.id, payment.id)
        when 'payment_intent.payment_failed'
          payment.update!(status: :failed)
          SyncDataToGhl.perform_async(payment.user.id, payment.id)
        end
        render_success(message: "PaymentIntent processed")
      else
        render_success(message: "Event acknowledged: #{event.type}")
      end

    rescue Stripe::SignatureVerificationError => e
      render_error(message: "Invalid signature", status: :bad_request)
    rescue StandardError => e
      Rails.logger.error "Webhook Error: #{e.message}"
      render_error(message: "Internal Server Error", status: :internal_server_error)
    end
  end

  private

  def process_success(payment, payment_intent)
    payment.update!(status: :succeeded, paid_at: Time.current)

    if payment.payment_type == 'down_payment'
      payment_method_id = payment_intent.payment_method
      user = payment.user

      Stripe::PaymentMethod.attach(payment_method_id, { customer: user.stripe_customer_id })
      Stripe::Customer.update(user.stripe_customer_id, { 
        invoice_settings: { default_payment_method: payment_method_id } 
      })
      
      user.payment_method&.update!(stripe_payment_method_id: payment_method_id)
    end

    payment.plan.update!(status: :completed) if payment.payment_type == 'full_payment'
  end
end
