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
    {
      success: response.code.to_i.between?(200, 299),
      status:  response.code.to_i,
      body:    (JSON.parse(response.body) rescue response.body)
    }
  end

  # Add one or more tags to a GHL contact.
  # GHL API: PUT /contacts/:id?locationId=<id>  with body { tags: ["tag1", "tag2"] }
  # Tags are additive — existing tags are preserved.
  def add_tags(contact_id, tags)
    tags = Array(tags).map(&:to_s).reject(&:blank?)
    return { success: false, status: 0, body: "No tags provided" } if tags.empty?

    url  = "/contacts/#{contact_id}?locationId=#{@location_id}"
    body = { tags: tags }.to_json
    Rails.logger.info("[GhlService#add_tags] contact_id=#{contact_id} location_id=#{@location_id} tags=#{tags.inspect}")
    response = self.class.put(url, @options.merge(body: body))
    Rails.logger.info("[GhlService#add_tags] status=#{response.code} contact_id=#{contact_id}")
    {
      success: response.code.to_i.between?(200, 299),
      status:  response.code.to_i,
      body:    (JSON.parse(response.body) rescue response.body)
    }
  end

  # Fetch a single contact by ID — returns full contact hash including
  # address1, city, state, postalCode, country, email, phone.
  def get_contact(contact_id)
    url = "/contacts/#{contact_id}"
    response = self.class.get(url, @options)
    {
      success: response.code.to_i.between?(200, 299),
      status:  response.code.to_i,
      body:    (JSON.parse(response.body) rescue response.body)
    }
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
      status:  response.code.to_i,
      body:    (JSON.parse(response.body) rescue response.body)
    }

    puts "GHL Search Final Result: #{result[:success] ? 'SUCCESS' : 'FAILED'}"
    result
  end
end
