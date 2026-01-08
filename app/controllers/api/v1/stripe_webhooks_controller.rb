class Api::V1::StripeWebhooksController < ActionController::API
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
end
