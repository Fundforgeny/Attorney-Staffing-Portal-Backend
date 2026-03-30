class GhlInboundWebhookService
  # Payment event webhook — separate from the login/magic-link webhook in GhlWebhookService.
  #
  # RULE: Every field listed in NUMERIC_FIELDS, TEXT_FIELDS, and DATE_FIELDS MUST be
  # populated on EVERY webhook call, regardless of which event is firing.
  # GHL uses the full payload to update the contact record on every trigger —
  # missing fields will leave stale or blank data in GHL.
  # Workers must never omit, skip, or conditionally exclude any field.
  # If a value is genuinely unavailable, use 0 for numeric, "NA" for text/date.
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
    phone
    payment_type
    payment_status
    status
    trigger
    firm_name
    firm_slug
    overdue
    next_payment_date
    financing_agreement_url
    engagement_letter_url
  ].freeze

  DATE_FIELDS = %i[next_payment_due last_paid date_processed].freeze

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

    value.is_a?(String) ? value.to_f : value
  end

  def normalize_text(value)
    # Text fields: send empty string rather than "NA" so GHL accepts them
    value.to_s.presence || ""
  end

  def normalize_date(value)
    # Date fields: send nil/null when no value — GHL rejects "NA" for date/numeric custom fields
    v = value.to_s.presence
    return nil if v.nil? || v == "NA"

    v
  end
end
