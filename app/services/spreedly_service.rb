# app/services/spreedly_service.rb
class SpreedlyService
  include HTTParty
  base_uri 'https://core.spreedly.com/v1'
  
  def initialize(user, plan, payment_params)
    @user = user
    @plan = plan
    @payment_params = payment_params
    @environment_key = ENV["SPREEDLY_ENVIRONMENT_KEY"]
    @access_secret = ENV["SPREEDLY_ACCESS_SECRET"]
    @options = {
      basic_auth: { username: @environment_key, password: @access_secret },
      headers: {
        "Content-Type" => "application/json"
      }
    }
  end
  
  def process_payment
    ActiveRecord::Base.transaction do
      payment_method = update_payment_method
      payment = find_payment
      result = make_purchase(payment, payment_method.vault_token)
      
      if result[:success]
        update_payment_status(payment, result[:body]["transaction"])
        return {
          success: true,
          data: {
            transaction_token: result[:body]["transaction"]["token"],
            state: result[:body]["transaction"]["state"],
            amount: result[:body]["transaction"]["amount"],
            currency: result[:body]["transaction"]["currency_code"],
            payment_type: payment.payment_type
          }
        }
      else
        error_message = extract_spreedly_error(result[:body])
        return { success: false, error: "Payment failed: #{error_message}", status: :payment_required }
      end
    end
  rescue StandardError => e
    puts "Payment processing error: #{e.class} - #{e.message}"
    puts "#{e.backtrace.join("\n")}"
    { success: false, error: "Payment processing failed: #{e.message}", status: :internal_server_error }
  end
  
  def purchase_payment(gateway_token, vault_token, amount, currency = 'USD', options = {})
    body = {
      transaction: {
        payment_method_token: vault_token,
        amount: amount,
        currency_code: currency,
        retain_on_success: options[:retain_on_success] || false
      }
    }
    endpoint = "/gateways/#{gateway_token}/purchase.json"
    
    response = self.class.post(endpoint, @options.merge(body: body.to_json))
    parse_response(response)
  end
  
  def verify_payment_method(vault_token)
    body = {
      transaction: {
        payment_method_token: vault_token
      }
    }
    
    response = self.class.post('/verify.json', @options.merge(body: body.to_json))
    parse_response(response)
  end
  
  def get_payment_method(vault_token)
    response = self.class.get("/payment_methods/#{vault_token}.json", @options)
    parse_response(response)
  end
  
  def retain_payment_method(vault_token)
    response = self.class.put("/payment_methods/#{vault_token}/retain.json", @options)
    parse_response(response)
  end
  
  private
  
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
  
  def make_purchase(payment, vault_token)
    amount_in_cents = (payment.total_payment_including_fee * 100).to_i
    
    purchase_options = {
      retain_on_success: payment.payment_type == "down_payment"
    }
    purchase_payment(ENV["GATEWAY_TOKEN"], vault_token, amount_in_cents, 'USD', purchase_options)
  end
  
  def update_payment_status(payment, transaction_data)
    payment.update!(
      charge_id: transaction_data["token"],
      status: transaction_data["state"]&.downcase,
      paid_at: Time.current
    )
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
  
  def parse_response(response)
    {
      success: response.code.to_i.between?(200, 299),
      status: response.code.to_i,
      body: (JSON.parse(response.body) rescue response.body)
    }
  end
end
