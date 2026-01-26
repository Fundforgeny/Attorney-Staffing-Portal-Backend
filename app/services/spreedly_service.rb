# app/services/spreedly_service.rb
class SpreedlyService
  include HTTParty
  base_uri 'https://core.spreedly.com/v1'
  
  def initialize
    @environment_key = ENV["SPREEDLY_ENVIRONMENT_KEY"]
    @access_secret = ENV["SPREEDLY_ACCESS_SECRET"]
    @options = {
      basic_auth: { username: @environment_key, password: @access_secret },
      headers: {
        "Content-Type" => "application/json"
      }
    }
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
  
  def parse_response(response)
    {
      success: response.code.to_i.between?(200, 299),
      status: response.code.to_i,
      body: (JSON.parse(response.body) rescue response.body)
    }
  end
end
