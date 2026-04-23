# ManualPortalPaymentService
#
# Handles a client-initiated manual payment from the customer portal.
# Uses the Spreedly vault token on the selected PaymentMethod.
#
# Behavior:
#   - Creates a new Payment record of type monthly_payment (or full_payment if no plan)
#   - Charges the vault token via Spreedly purchase
#   - On success: marks payment succeeded, fires GHL installment_payment_successful alert,
#     triggers cancel_open_retries_if_covered! via after_commit
#   - On failure: marks payment failed, fires GHL payment_failed alert
#
# Partial payments (amount < installment) are accepted — retries continue until the
# cumulative total for the billing month meets or exceeds the installment amount.
#
class ManualPortalPaymentService
  FEE_PERCENTAGE = PaymentPlanFeeCalculator::FEE_PERCENTAGE

  def initialize(plan:, payment_method:, amount:, user:)
    @plan           = plan
    @payment_method = payment_method
    @amount         = amount.to_d
    @user           = user
    @client         = Spreedly::Client.new
  end

  def call
    payment = build_payment_record!
    transaction = attempt_charge!(payment)

    if transaction_succeeded?(transaction)
      finalize_success!(payment, transaction)
      { success: true, payment: payment }
    else
      error_message = extract_error(transaction)
      finalize_failure!(payment, transaction, error_message)
      { success: false, payment: payment, error: error_message }
    end
  rescue StandardError => e
    Rails.logger.error("[ManualPortalPayment] Error for plan_id=#{@plan.id}: #{e.class}: #{e.message}")
    { success: false, error: e.message }
  end

  private

  attr_reader :plan, :payment_method, :amount, :user, :client

  def build_payment_record!
    fee            = (amount * FEE_PERCENTAGE).round(2)
    total_with_fee = amount + fee

    plan.payments.create!(
      user:                        user,
      payment_method:              payment_method,
      payment_type:                plan.payment_plan_selected? ? :monthly_payment : :full_payment,
      payment_amount:              amount,
      transaction_fee:             fee,
      total_payment_including_fee: total_with_fee,
      status:                      :processing,
      scheduled_at:                Time.current,
      retry_count:                 0
    )
  end

  def attempt_charge!(payment)
    amount_cents = (payment.total_payment_including_fee * 100).to_i

    payload = {
      transaction: {
        payment_method_token: payment_method.vault_token,
        amount:               amount_cents,
        currency_code:        "USD",
        retain_on_success:    false,
        description:          "Manual portal payment — #{plan.name}"
      }
    }

    workflow_key = ENV["SPREEDLY_WORKFLOW_KEY"].presence || ENV["SPREEDLY_COMPOSER_WORKFLOW_KEY"].presence
    payload[:transaction][:workflow_key] = workflow_key if workflow_key.present?

    response = client.post("/transactions/purchase.json", body: payload)
    response.fetch("transaction")
  end

  def finalize_success!(payment, transaction)
    payment.update!(
      status:                   :succeeded,
      charge_id:                transaction["token"],
      processor_transaction_id: transaction["gateway_transaction_id"].presence,
      paid_at:                  Time.current
    )

    plan.refresh_next_payment_at!

    GhlInboundWebhookWorker.perform_async(
      payment.id,
      GhlInboundWebhookService::INSTALLMENT_PAYMENT_SUCCESSFUL_EVENT
    )

    Rails.logger.info("[ManualPortalPayment] SUCCESS plan_id=#{plan.id} payment_id=#{payment.id} amount=#{amount}")
  end

  def finalize_failure!(payment, transaction, error_message)
    payment.update!(
      status:                   :failed,
      charge_id:                transaction&.dig("token"),
      processor_transaction_id: transaction&.dig("gateway_transaction_id").presence,
      decline_reason:           error_message
    )

    GhlInboundWebhookWorker.perform_async(
      payment.id,
      GhlInboundWebhookService::PAYMENT_FAILED_EVENT
    )

    Rails.logger.warn("[ManualPortalPayment] FAILED plan_id=#{plan.id} payment_id=#{payment.id} reason=#{error_message}")
  end

  def transaction_succeeded?(transaction)
    return false if transaction.blank?
    ActiveModel::Type::Boolean.new.cast(transaction["succeeded"]) ||
      transaction["state"].to_s == "succeeded"
  end

  def extract_error(transaction)
    return "Payment failed" if transaction.blank?
    transaction["message"].presence ||
      transaction.dig("gateway_specific_response_fields", "message").presence ||
      transaction["state"].presence ||
      "Payment failed"
  end
end
