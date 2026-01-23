# app/services/ghl_service.rb
class GhlService
  include HTTParty
  base_uri 'https://services.leadconnectorhq.com'

  def initialize(api_key, location_id)
    @location_id = location_id
    @options = {
      headers: {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type" => "application/json",
        "Version" => "2021-07-28"
      }
    }
  end

  def update_contact(contact_id, custom_fields)
    puts "Updating GHL contact #{contact_id}."
    
    body = {
      customFields: custom_fields.map { |id, value| { id: id, value: value } }
    }
    
    url = "/contacts/#{contact_id}?locationId=#{@location_id}"    
    puts "Sending request to GHL API..."
    response = self.class.put(url, @options.merge(body: body.to_json))
    
    puts "GHL Response Status: #{response.code}"    
    result = {
      success: response.code.to_i.between?(200, 299),
      status: response.code.to_i,
      body: (JSON.parse(response.body) rescue response.body)
    }
    
    result
  end

  def search_contacts(email)
    query_params = {
      locationId: @location_id,
      query: email
    }.to_query

    url = "/contacts/?#{query_params}"
    response = self.class.get(url, @options)
    result = {
      success: response.code.to_i.between?(200, 299),
      status: response.code.to_i,
      body: (JSON.parse(response.body) rescue response.body)
    }
    
    puts "GHL Search Final Result: #{result[:success] ? 'SUCCESS' : 'FAILED'}"
    result
  end
end
