# app/services/spreedly_service.rb
class SpreedlyService
  def initialize(user, plan, payment_params)
    @user = user
    @plan = plan
    @payment_params = payment_params
    @client = Spreedly::Client.new
  end
  
  def process_payment
    ActiveRecord::Base.transaction do
      payment_method = update_payment_method
      payment = find_payment
      transaction = authorize_payment(payment, payment_method.vault_token)
      if transaction_succeeded?(transaction)
        update_payment_status(payment, transaction, :succeeded)
        return {
          success: true,
          data: {
            transaction_token: transaction["token"],
            state: transaction["state"],
            amount: transaction["amount"],
            currency: transaction["currency_code"],
            payment_type: payment.payment_type
          }
        }
      else
        update_payment_status(payment, transaction, :failed)
        error_message = extract_spreedly_error(transaction)
        return { success: false, error: "Payment failed: #{error_message}", status: :payment_required }
      end
    rescue Spreedly::Error => e
      update_payment_status(payment, e.payload["transaction"], :failed) if payment.present?
      error_message = extract_spreedly_error(e.payload)
      return { success: false, error: "Payment failed: #{error_message}", status: :payment_required }
    end
  rescue StandardError => e
    puts "Payment processing error: #{e.class} - #{e.message}"
    puts "#{e.backtrace.join("\n")}"
    { success: false, error: "Payment processing failed: #{e.message}", status: :internal_server_error }
  end

  def verify_payment_method(vault_token)
    @client.post(
      "/verify.json",
      body: {
        transaction: {
          payment_method_token: vault_token
        }
      }
    )
  end

  def get_payment_method(vault_token)
    @client.get("/payment_methods/#{vault_token}.json")
  end

  def retain_payment_method(vault_token)
    @client.put("/payment_methods/#{vault_token}/retain.json")
  end

  private

  def authorize_payment(payment, vault_token)
    amount_in_cents = (payment.total_payment_including_fee * 100).to_i

    payload = {
      transaction: {
        payment_method_token: vault_token,
        amount: amount_in_cents,
        currency_code: "USD",
        retain_on_success: payment.payment_type == "down_payment"
      }
    }
    workflow_key = composer_workflow_key
    payload[:transaction][:workflow_key] = workflow_key if workflow_key.present?
  
    response = @client.post("/transactions/authorize.json", body: payload)
    response.fetch("transaction")
  end

  def update_payment_method
    payment_method = @user.payment_method || @user.build_payment_method

    payment_method.update!(
      provider: "Spreedly Vault",
      vault_token: @payment_params[:vault_token],
      card_brand: @payment_params[:card_brand]
    )
    payment_method
  end
  
  def find_payment
    payment_type = @plan&.duration > 0 ? "down_payment" : "full_payment"
    payment = Payment.find_by(user: @user, plan: @plan, payment_type: payment_type)
    
    unless payment && payment.total_payment_including_fee.present?
      raise ArgumentError, "Payment not found"
    end
    
    payment
  end
  
  def update_payment_status(payment, transaction_data, status)
    payment.update!(
      charge_id: transaction_data&.dig("token") || payment.charge_id,
      status: status,
      paid_at: status.to_sym == :succeeded ? Time.current : nil
    )
  end

  def transaction_succeeded?(transaction_data)
    return false if transaction_data.blank?

    ActiveModel::Type::Boolean.new.cast(transaction_data["succeeded"]) || transaction_data["state"].to_s == "succeeded"
  end
  
  def composer_workflow_key
    ENV["SPREEDLY_WORKFLOW_KEY"].presence || ENV["SPREEDLY_COMPOSER_WORKFLOW_KEY"].presence
  end

  def extract_spreedly_error(response_body)
    if response_body.is_a?(Hash) && response_body["transaction"]
      error_message = response_body["transaction"]["message"]
      return error_message if error_message.present?
    end
    
    if response_body.is_a?(Hash) && response_body["errors"]
      errors = response_body["errors"]
      if errors.is_a?(Array) && errors.first
        return errors.first["message"] || errors.first["key"]
      end
    end
    "Payment processing failed"
  end
end
