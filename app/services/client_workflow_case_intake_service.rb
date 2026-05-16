class ClientWorkflowCaseIntakeService
  PROVIDER = "ghl".freeze
  EXTERNAL_OBJECT_TYPE = "client_workflow_event".freeze
  DEFAULT_FIRM_NAME = "Titans Law".freeze

  Result = Struct.new(:case_record, :case_intake, :staffing_requirement, :created, keyword_init: true)

  def initialize(payload)
    @payload = payload.to_h.deep_symbolize_keys
  end

  def call
    validate_payload!

    ActiveRecord::Base.transaction do
      existing_sync = find_existing_sync_record

      if existing_sync
        case_record = existing_sync.syncable
        created = false
      else
        case_record = build_case_record
        created = true
      end

      update_case_record!(case_record)
      case_intake = upsert_case_intake!(case_record)
      upsert_related_parties!(case_record)
      upsert_case_tasks!(case_record)
      staffing_requirement = upsert_staffing_requirement!(case_record)
      upsert_sync_record!(case_record)

      Result.new(
        case_record: case_record,
        case_intake: case_intake,
        staffing_requirement: staffing_requirement,
        created: created
      )
    end
  end

  private

  attr_reader :payload

  def validate_payload!
    raise ArgumentError, "external_event_id or contact_id is required" if external_event_id.blank?
    raise ArgumentError, "client.email is required" if client_email.blank?
    raise ArgumentError, "case.title is required" if case_payload[:title].blank?
  end

  def external_event_id
    payload[:external_event_id].presence ||
      payload[:workflow_event_id].presence ||
      payload[:event_id].presence ||
      derived_contact_type_event_id
  end

  def derived_contact_type_event_id
    return nil if ghl_contact_id.blank?

    workflow_id = payload[:workflow_id].presence || payload[:workflow_name].presence || "client_workflow"
    contact_type = contact_type_payload[:new_contact_type].presence || contact_type_payload[:contact_type].presence || payload[:contact_type].presence || "customer"
    "contact_type_change:#{workflow_id}:#{ghl_contact_id}:#{contact_type}"
  end

  def source
    payload[:source].presence || "ghl_contact_type_change"
  end

  def firm
    @firm ||= begin
      location_id = payload[:location_id].presence || payload.dig(:ghl, :location_id).presence
      firm_scope = Firm.all
      found = firm_scope.find_by(location_id: location_id) if location_id.present?
      found ||= firm_scope.find_by(name: firm_name)
      found ||= Firm.create!(name: firm_name, location_id: location_id)
      found
    end
  end

  def firm_name
    payload[:firm_name].presence || payload.dig(:firm, :name).presence || DEFAULT_FIRM_NAME
  end

  def client_user
    @client_user ||= begin
      user = User.find_or_initialize_by(email: client_email.downcase.strip)
      user.first_name = client_payload[:first_name].presence || user.first_name
      user.last_name = client_payload[:last_name].presence || user.last_name
      user.phone = client_payload[:phone].presence || user.phone if user.respond_to?(:phone=)
      user.user_type = :client if user.user_type.blank?
      user.firm ||= firm if user.respond_to?(:firm=)
      user.save!
      user
    end
  end

  def client_payload
    payload[:client].to_h.symbolize_keys
  end

  def client_email
    client_payload[:email].presence || payload[:email].presence
  end

  def case_payload
    payload[:case].to_h.symbolize_keys
  end

  def intake_payload
    payload[:intake].to_h.symbolize_keys
  end

  def staffing_payload
    payload[:staffing_requirement].to_h.symbolize_keys
  end

  def find_existing_sync_record
    ExternalSyncRecord.find_by(
      provider: PROVIDER,
      external_object_type: EXTERNAL_OBJECT_TYPE,
      external_id: external_event_id
    )
  end

  def build_case_record
    Case.new(firm: firm, created_by: client_user, client_user: client_user)
  end

  def update_case_record!(case_record)
    case_record.assign_attributes(
      firm: firm,
      created_by: case_record.created_by || client_user,
      client_user: client_user,
      title: case_payload[:title],
      description: case_payload[:description].presence || intake_payload[:case_text].presence || case_record.description,
      jurisdiction: case_payload[:jurisdiction].presence || staffing_payload[:jurisdiction].presence || case_record.jurisdiction,
      county: case_payload[:county].presence || staffing_payload[:county].presence || case_record.county,
      zip_code: case_payload[:zip_code].presence || staffing_payload[:zip_code].presence || case_record.zip_code,
      practice_areas: array_value(case_payload[:practice_areas].presence || staffing_payload[:practice_areas].presence || case_record.practice_areas),
      status: case_payload[:status].presence || case_record.status || "open",
      matter_status: case_payload[:matter_status].presence || case_record.matter_status || "intake_received",
      staffing_status: case_payload[:staffing_status].presence || case_record.staffing_status || "not_started",
      open_date: parse_date(case_payload[:open_date]) || case_record.open_date || Date.current,
      retainer_amount: decimal_value(case_payload[:retainer_amount]) || case_record.retainer_amount,
      budget_amount: decimal_value(case_payload[:budget_amount]) || decimal_value(case_payload[:budget]) || case_record.budget_amount,
      clio_matter_id: case_payload[:clio_matter_id].presence || case_record.clio_matter_id,
      custom_data: (case_record.custom_data || {}).merge(case_custom_data)
    )

    case_record.save!
    case_record
  end

  def case_custom_data
    {
      "source" => source,
      "external_event_id" => external_event_id,
      "ghl_contact_id" => ghl_contact_id,
      "ghl_opportunity_id" => ghl_opportunity_id,
      "workflow_id" => payload[:workflow_id].presence,
      "workflow_name" => payload[:workflow_name].presence,
      "trigger" => trigger_payload,
      "contact_type_change" => contact_type_payload,
      "ads_attribution" => ads_attribution_payload,
      "payment" => payload[:payment].presence
    }.compact
  end

  def upsert_case_intake!(case_record)
    intake = case_record.case_intakes.find_or_initialize_by(
      source: source,
      ghl_contact_id: ghl_contact_id,
      ghl_opportunity_id: ghl_opportunity_id
    )

    intake.assign_attributes(
      review_status: intake_payload[:review_status].presence || "pending_review",
      confidence: decimal_value(intake_payload[:confidence]),
      transcript: intake_payload[:transcript].presence || intake_payload[:call_transcript].presence,
      raw_payload: payload,
      ai_extraction: intake_payload[:ai_extraction].presence || payload[:ai_extraction].presence || {}
    )

    intake.save!
    intake
  end

  def upsert_related_parties!(case_record)
    Array(payload[:related_parties]).each do |party_payload|
      party = party_payload.to_h.symbolize_keys
      next if party[:name].blank?

      existing = case_record.related_parties.where("LOWER(name) = ?", party[:name].to_s.downcase).first
      related_party = existing || case_record.related_parties.build(name: party[:name])
      related_party.assign_attributes(
        role: party[:role].presence || related_party.role || "unknown",
        email: party[:email].presence || related_party.email,
        phone: party[:phone].presence || related_party.phone,
        represented_status: party[:represented_status].presence || related_party.represented_status,
        counsel_name: party[:counsel_name].presence || related_party.counsel_name,
        counsel_email: party[:counsel_email].presence || related_party.counsel_email,
        counsel_phone: party[:counsel_phone].presence || related_party.counsel_phone,
        clio_contact_id: party[:clio_contact_id].presence || related_party.clio_contact_id,
        custom_data: (related_party.custom_data || {}).merge(party[:custom_data].to_h.stringify_keys)
      )
      related_party.save!
    end
  end

  def upsert_case_tasks!(case_record)
    Array(payload[:case_tasks]).each do |task_payload|
      task = task_payload.to_h.symbolize_keys
      next if task[:title].blank?

      existing = case_record.case_tasks.where("LOWER(title) = ?", task[:title].to_s.downcase).first
      case_task = existing || case_record.case_tasks.build(title: task[:title])
      case_task.assign_attributes(
        description: task[:description].presence || case_task.description,
        priority: task[:priority].presence || case_task.priority || "normal",
        status: task[:status].presence || case_task.status || "open",
        source: task[:source].presence || "ai",
        due_at: parse_time(task[:due_at] || task[:due_date]) || case_task.due_at,
        clio_task_id: task[:clio_task_id].presence || case_task.clio_task_id,
        custom_data: (case_task.custom_data || {}).merge(task[:custom_data].to_h.stringify_keys)
      )
      case_task.save!
    end
  end

  def upsert_staffing_requirement!(case_record)
    requirement = case_record.staffing_requirements.order(created_at: :desc).first || case_record.staffing_requirements.build
    requirement.assign_attributes(
      status: staffing_payload[:status].presence || requirement.status || "draft",
      urgency: staffing_payload[:urgency].presence || requirement.urgency || "standard",
      required_license_states: array_value(staffing_payload[:required_license_states].presence || staffing_payload[:license_states]),
      federal_court_admissions: array_value(staffing_payload[:federal_court_admissions]),
      practice_areas: array_value(staffing_payload[:practice_areas].presence || case_record.practice_areas),
      county: staffing_payload[:county].presence || case_record.county,
      zip_code: staffing_payload[:zip_code].presence || case_record.zip_code,
      residency_required: boolean_value(staffing_payload[:residency_required], default: true),
      target_interview_count: integer_value(staffing_payload[:target_interview_count]) || requirement.target_interview_count || 5,
      custom_data: (requirement.custom_data || {}).merge(staffing_payload[:custom_data].to_h.stringify_keys).merge("ads_attribution" => ads_attribution_payload).compact
    )
    requirement.save!
    requirement
  end

  def upsert_sync_record!(case_record)
    record = case_record.external_sync_records.find_or_initialize_by(
      provider: PROVIDER,
      external_object_type: EXTERNAL_OBJECT_TYPE,
      external_id: external_event_id
    )

    record.assign_attributes(status: "synced", last_synced_at: Time.current, metadata: { source: source })
    record.save!
  end

  def trigger_payload
    payload[:trigger].to_h.stringify_keys.presence || {
      "type" => payload[:trigger_type].presence || "contact_type_change",
      "source" => source
    }.compact
  end

  def contact_type_payload
    payload[:contact_type_change].to_h.symbolize_keys.presence || {
      contact_type: payload[:contact_type].presence,
      previous_contact_type: payload[:previous_contact_type].presence,
      new_contact_type: payload[:new_contact_type].presence || payload[:customer_contact_type].presence || payload[:contact_type].presence,
      changed_at: payload[:contact_type_changed_at].presence || payload[:changed_at].presence
    }.compact
  end

  def ads_attribution_payload
    payload[:ads_attribution].presence || payload[:ad_attribution].presence || payload[:ads_reporting].presence || payload[:utm].presence || {}
  end

  def ghl_contact_id
    payload[:ghl_contact_id].presence || payload[:contact_id].presence || payload.dig(:ghl, :contact_id).presence
  end

  def ghl_opportunity_id
    payload[:ghl_opportunity_id].presence || payload[:opportunity_id].presence || payload.dig(:ghl, :opportunity_id).presence
  end

  def array_value(value)
    case value
    when Array
      value.map(&:to_s).reject(&:blank?)
    when String
      value.split(/[;,]/).map(&:strip).reject(&:blank?)
    else
      []
    end
  end

  def decimal_value(value)
    return nil if value.blank?

    BigDecimal(value.to_s.gsub(/[$,]/, ""))
  rescue ArgumentError
    nil
  end

  def integer_value(value)
    return nil if value.blank?

    value.to_i
  end

  def boolean_value(value, default: false)
    return default if value.nil? || value == ""
    return value if value == true || value == false

    %w[true yes 1 y].include?(value.to_s.downcase)
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
