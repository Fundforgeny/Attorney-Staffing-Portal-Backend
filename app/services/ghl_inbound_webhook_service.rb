class GhlInboundWebhookService
  # Payment event webhook — separate from the login/magic-link webhook in GhlWebhookService
  STATIC_WEBHOOK_URL = "https://services.leadconnectorhq.com/hooks/ypwiHcCIbSqZMzXzrIhd/webhook-trigger/d3d0e182-2544-4601-8ab5-636e9663c2f8".freeze
  PAYMENT_SUCCESSFUL_EVENT             = "payment successful".freeze
  INSTALLMENT_PAYMENT_SUCCESSFUL_EVENT = "installment payment successful".freeze
  PAYMENT_FAILED_EVENT                 = "payment failed".freeze
  PAYMENT_PLAN_CREATED_EVENT           = "payment plan created".freeze
  SEVEN_DAY_REMINDER_EVENT             = "7 day reminder".freeze
  TWENTY_FOUR_HOUR_REMINDER_EVENT = "24 hour reminder".freeze
  THIRTY_DAYS_LATE_EVENT          = "30 days late".freeze
  CHARGEBACK_EVENT                = "chargeback".freeze

  NUMERIC_FIELDS = %i[
    down_payment
    payment_amount
    installment_amount
    total_amount
    remaining_balance
  ].freeze

  TEXT_FIELDS = %i[
    email
    first_name
    last_name
    payment_type
    payment_status
    status
    trigger
    firm_name
    financing_agreement_url
    engagement_letter_url
  ].freeze

  DATE_FIELDS = %i[next_payment_due last_paid].freeze

  def initialize(webhook_url = STATIC_WEBHOOK_URL)
    @webhook_url = webhook_url
  end

  def self.resolve_webhook_url
    STATIC_WEBHOOK_URL
  end

  # Returns the appropriate event trigger for a given payment:
  # - PAYMENT_FAILED_EVENT for failed payments
  # - INSTALLMENT_PAYMENT_SUCCESSFUL_EVENT for recurring scheduled installments on an existing plan
  # - PAYMENT_SUCCESSFUL_EVENT for all other successful payments (early payoffs, lump sums, etc.)
  def self.default_event_for_payment(payment)
    return PAYMENT_FAILED_EVENT if payment&.failed?
    return INSTALLMENT_PAYMENT_SUCCESSFUL_EVENT if payment&.monthly_payment?

    PAYMENT_SUCCESSFUL_EVENT
  end

  def self.plan_created_event
    PAYMENT_PLAN_CREATED_EVENT
  end

  def call(payload, context: {})
    uri = URI.parse(@webhook_url)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(normalize_payload(payload))

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: 15,
      read_timeout: 30
    ) do |http|
      http.request(request)
    end

    Rails.logger.info("[GHL Payment Webhook] status=#{response.code} context=#{context} body=#{response.body}")
    raise StandardError, "GHL payment webhook failed with status #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response
  rescue StandardError => e
    Rails.logger.error("[GHL Payment Webhook] request_failed context=#{context} error=#{e.class}: #{e.message}")
    raise e
  end

  private

  def normalize_payload(payload)
    normalized = payload.to_h.deep_symbolize_keys

    NUMERIC_FIELDS.each do |field|
      normalized[field] = normalize_numeric(normalized[field])
    end

    TEXT_FIELDS.each do |field|
      normalized[field] = normalize_text(normalized[field])
    end

    DATE_FIELDS.each do |field|
      normalized[field] = normalize_date(normalized[field])
    end

    normalized[:status] = normalized[:status].presence || normalized[:payment_status].presence || PAYMENT_SUCCESSFUL_EVENT
    normalized[:trigger] = normalized[:trigger].presence || normalized[:status]
    normalized[:payment_status] = normalized[:payment_status].presence || normalized[:status]

    normalized
  end

  def normalize_numeric(value)
    return 0 if value.blank?

    value.is_a?(String) ? value.presence || "0" : value
  end

  def normalize_text(value)
    value.to_s.presence || "NA"
  end

  def normalize_date(value)
    value.to_s.presence || "NA"
  end
end
