module Admin
  class ManualVaultChargeService
    def initialize(plan:, amount:, description: nil, payment_method: nil)
      @plan = plan
      @user = plan.user
      @amount = parse_amount(amount)
      @description = description.to_s.presence || "Admin manual payment"
      @explicit_payment_method = payment_method
      @client = Spreedly::Client.new
    end

    def call
      validate_inputs!

      payment = create_payment!
      transaction = purchase!(payment)

      if transaction_succeeded?(transaction)
        finalize_success!(payment, transaction)
      else
        finalize_failure!(payment, transaction)
      end
      payment
    end

    private

    attr_reader :plan, :user, :amount, :description, :client

    def validate_inputs!
      raise ArgumentError, "Plan user not found" if user.blank?
      raise ArgumentError, "Amount must be a valid number" if amount.blank?
      raise ArgumentError, "Amount must be greater than 0" if amount <= 0
      raise ArgumentError, "No saved payment method found" if payment_method.blank?
      raise ArgumentError, "Saved payment method is missing a vault token" if payment_method.vault_token.blank?
    end

    def payment_method
      @payment_method ||= @explicit_payment_method || user.payment_methods.ordered_for_user.first
    end

    def create_payment!
      Payment.create!(
        plan: plan,
        user: user,
        payment_method: payment_method,
        payment_type: manual_payment_type,
        payment_amount: amount,
        total_payment_including_fee: amount,
        transaction_fee: 0,
        status: :processing,
        scheduled_at: Time.current
      )
    end

    def purchase!(payment)
      # Sync missing billing data from GHL before charging
      GhlBillingSyncService.new(user).sync_if_needed! rescue nil
      user.reload

      billing = {
        name:     user.full_name.presence,
        address1: user.address_street.presence,
        city:     user.city.presence,
        state:    user.state.presence,
        zip:      user.postal_code.presence,
        country:  (user.country.presence || "US").then { |c| c.length > 2 ? country_code_for(c) : c }
      }.compact

      payload = {
        transaction: {
          payment_method_token: payment_method.vault_token,
          amount:               (payment.total_payment_including_fee.to_d * 100).to_i,
          currency_code:        "USD",
          retain_on_success:    false,
          description:          description,
          # ── Stripe Radar required signals ──────────────────────────────────────
          # Passing email, name, and billing address dramatically improves fraud
          # model accuracy and prevents Radar from blocking legitimate charges.
          # See: https://docs.stripe.com/radar/optimize-risk-factors
          email:                user.email.presence
        }.tap { |t|
          t[:billing_address] = billing unless billing.empty?
          t.delete(:email) if t[:email].blank?
        }
      }

      workflow_key = ENV["SPREEDLY_WORKFLOW_KEY"].presence || ENV["SPREEDLY_COMPOSER_WORKFLOW_KEY"].presence || "01KFECKTHBXNNDGX1A4RSDDCKJ"
      payload[:transaction][:workflow_key] = workflow_key if workflow_key.present?

      response = client.post("/transactions/purchase.json", body: payload)
      response.fetch("transaction")
    rescue Spreedly::Error => e
      transaction = e.payload.is_a?(Hash) ? e.payload["transaction"] : nil
      finalize_failure!(payment, transaction)
    end

    def country_code_for(name)
      return name if name.blank? || name.length == 2
      {
        "united states" => "US", "usa" => "US",
        "canada" => "CA", "united kingdom" => "GB",
        "australia" => "AU", "mexico" => "MX"
      }.fetch(name.downcase.strip, name)
    end

    def finalize_success!(payment, transaction)
      payment.update!(
        status:                   :succeeded,
        charge_id:                transaction["token"] || payment.charge_id,
        processor_transaction_id: transaction["gateway_transaction_id"].presence || payment.processor_transaction_id,
        paid_at:                  Time.current
      )

      plan.update!(status: :paid) if plan.remaining_balance_logic <= 0
      SyncDataToGhl.perform_async(user.id, payment.id)
      GhlInboundWebhookWorker.perform_async(payment.id)
      payment
    end

    def finalize_failure!(payment, transaction)
      payment.update!(
        status:                   :failed,
        charge_id:                transaction&.dig("token") || payment.charge_id,
        processor_transaction_id: transaction&.dig("gateway_transaction_id").presence || payment.processor_transaction_id,
        paid_at:                  nil
      )

      SyncDataToGhl.perform_async(user.id, payment.id)
      GhlInboundWebhookWorker.perform_async(payment.id, GhlInboundWebhookService::PAYMENT_FAILED_EVENT)
      raise StandardError, extract_error_message(transaction)
    end

    def extract_error_message(transaction)
      return "Manual charge failed" if transaction.blank?

      transaction["message"].presence || transaction["state"].presence || "Manual charge failed"
    end

    def transaction_succeeded?(transaction)
      ActiveModel::Type::Boolean.new.cast(transaction["succeeded"]) || transaction["state"].to_s == "succeeded"
    end

    def manual_payment_type
      plan.payment_plan_selected? ? :monthly_payment : :full_payment
    end

    def parse_amount(value)
      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
