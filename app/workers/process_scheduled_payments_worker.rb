# app/workers/process_scheduled_payments_worker.rb
class ProcessScheduledPaymentsWorker
  include Sidekiq::Worker

  def perform
    today = Date.current
    Payment.where(scheduled_at: today.beginning_of_day..today.end_of_day, status: :pending).find_each do |payment|
      ChargePaymentWorker.perform_async(payment.id)
    end
  end
end

# app/workers/charge_payment_worker.rb
class ChargePaymentWorker
  include Sidekiq::Worker
  sidekiq_options retry: 5

  def perform(payment_id)
    payment = Payment.find(payment_id)
    return if payment.succeeded?

    payment.update!(status: :processing)

    intent = Stripe::PaymentIntent.create(
      amount: (payment.payment_amount * 100).to_i,
      currency: 'usd',
      customer: payment.user.stripe_customer_id,
      payment_method: payment.payment_method.stripe_payment_method_id,
      off_session: true,
      confirm: true,
      description: "Installment ##{payment.id} for #{payment.plan.name}"
    )

    if intent.status == 'succeeded'
      payment.update!(status: :succeeded, stripe_charge_id: intent.id, paid_at: Time.current)
    else
      payment.update!(status: :failed)
      # Optional: notify user, trigger dunning
    end
  rescue Stripe::CardError => e
    payment.update!(status: :failed)
    # handle declined card
  end
end
