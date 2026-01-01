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
