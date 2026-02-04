# app/workers/sync_data_to_ghl_worker.rb
class SyncDataToGhl
  include Sidekiq::Worker

  FIRM_CONFIGS = {
    "Ironclad" => {
      fields: { paid_client: "ZkX1fRUEFCuq3uYOr1Xd", payment_status: "x9ENgy8VOQpDL3jZdxLN", payment_type: "YYOpxP8jiIVSoY8rOHyU", engagement_url: "aP7RPCNBULEdJ3jq0O5g" },
      contact_id_method: :contact_id
    },
    "Titans Law" => {
      fields: { paid_client: "M6Xefb8UTtx299Nc5LRq", payment_status: "6oPNxcudlY8YR6EFAl4W", payment_type: "pF789Hucrb0oXL2JcdO8", engagement_url: "I43RI0Xqb678RbrOhaC9" },
      contact_id_method: :contact_id
    },
    "Fund Forge" => {
      fields: { payment_status: "a7Ujcj1JK385Zhnlmrlp", engagement_url: "UOCxNTUnL5Nq8Ik4un1P", financing_url: "3QAZ4jGrUFeczFTPSXkn", remaining_balance: "2GMCmUqXyzRDL3U689tj", payment_type: "cFye5sZSZFQgJhvaJFM2" },
      contact_id_method: :ghl_fund_forge_id
    }
  }.freeze

  def perform(user_id, payment_id)
    @user = User.find(user_id)
    @payment = Payment.find(payment_id)
    @plan = @payment.plan

    puts "Starting GHL sync for User ##{user_id} | Payment ##{payment_id}"
    sync_firm_by_name("Fund Forge", ENV["FUND_FORGE_API_KEY"], ENV["FUND_FORGE_LOCATION_ID"])

    user_firm = @user.firms.where.not(name: "Fund Forge").first
    if user_firm
      sync_firm_by_name(user_firm.name, user_firm.ghl_api_key, user_firm.location_id)
    else
      puts "No additional firm association found for User ##{user_id}"
    end

    puts "GHL sync completed for User ##{user_id}"
  rescue StandardError => e
    Rails.logger.error "GHL Sync failed: #{e.message}"
    raise e
  end

  private

  def sync_firm_by_name(firm_name, api_key, location_id)
    config = FIRM_CONFIGS[firm_name]
    return puts "Unknown firm: #{firm_name}, skipping" unless config

    firm_user = FirmUser.find_by(user: @user)
    contact_id = firm_user&.send(config[:contact_id_method])

    return puts "No #{firm_name} Contact ID found for User ##{@user.id}" if contact_id.blank?

    service = GhlService.new(api_key, location_id)
    payload = build_payload(config[:fields], firm_name)

    puts "Updating #{firm_name} (Contact: #{contact_id})"
    result = service.update_contact(contact_id, payload)
    
    unless result[:success]
      puts "#{firm_name} GHL Update FAILED: #{result[:body]}"
    end
  end

  def build_payload(mapping, firm_name)
    payload = {
      mapping[:payment_status] => @payment.status,
      mapping[:payment_type]   => (@payment.payment_type == 'full_payment' ? 'Paid in full(PIF)' : 'Payment Plan'),
      mapping[:engagement_url] => @plan.agreement&.engagement_pdf&.url
    }

    paid_client_status = check_paid_client_status

    payload[mapping[:paid_client]] = paid_client_status || nil if mapping[:paid_client]
    payload[mapping[:financing_url]] = @plan.agreement&.pdf&.url if mapping[:financing_url]
    payload[mapping[:remaining_balance]] = @plan.remaining_balance_logic if mapping[:remaining_balance]

    payload.compact
  end

  def check_paid_client_status
    thirty_days_ago = 30.days.ago
    successful_payments = Payment.joins(:plan)
                                  .where(plans: { user_id: @user.id })
                                  .where(status: :succeeded)
                                  .where('payments.created_at >= ?', thirty_days_ago)
    
    if successful_payments.exists?
      'paying'
    else
      'over due'
    end
  end
end
