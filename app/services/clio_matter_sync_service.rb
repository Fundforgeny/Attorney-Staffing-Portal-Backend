class ClioMatterSyncService
  Result = Struct.new(:case_record, :dry_run, :operations, :ready_for_live_sync, keyword_init: true)

  def initialize(case_record)
    @case_record = case_record
  end

  def dry_run
    Result.new(
      case_record: case_record,
      dry_run: true,
      operations: build_operations,
      ready_for_live_sync: ClioConfig.configured?
    )
  end

  def sync!
    ClioConfig.require_config!
    raise NotImplementedError, "Live Clio writes are intentionally gated until the dry-run packet is approved and endpoint payloads are verified."
  end

  private

  attr_reader :case_record

  def build_operations
    [client_contact_operation, matter_operation, note_operation, *related_party_operations, *task_operations].compact
  end

  def client_contact_operation
    client = case_record.client_user
    return nil unless client

    {
      action: "find_or_create_contact",
      local_type: "User",
      local_id: client.id,
      external_id: nil,
      payload: {
        first_name: client.first_name,
        last_name: client.last_name,
        name: client.full_name,
        email: client.email,
        phone: client.phone
      }.compact
    }
  end

  def matter_operation
    {
      action: case_record.clio_matter_id.present? ? "update_matter" : "create_matter",
      local_type: "Case",
      local_id: case_record.id,
      external_id: case_record.clio_matter_id,
      payload: {
        display_number: case_record.clio_matter_id,
        description: case_record.description,
        status: case_record.matter_status,
        location: case_record.jurisdiction,
        open_date: case_record.open_date&.iso8601,
        close_date: case_record.close_date&.iso8601,
        client_reference: case_record.client_user&.email,
        custom_data: {
          title: case_record.title,
          county: case_record.county,
          zip_code: case_record.zip_code,
          practice_areas: case_record.practice_areas || [],
          retainer_amount: case_record.retainer_amount&.to_f,
          budget_amount: case_record.budget_amount&.to_f,
          staffing_status: case_record.staffing_status
        }.compact
      }.compact
    }
  end

  def note_operation
    latest_intake = case_record.case_intakes.order(created_at: :desc).first
    return nil if latest_intake.blank? && case_record.description.blank?

    {
      action: "create_note",
      local_type: "Case",
      local_id: case_record.id,
      external_id: nil,
      payload: {
        subject: "Titans intake summary",
        detail: [
          case_record.description,
          latest_intake&.ai_extraction.presence,
          latest_intake&.transcript.presence
        ].compact.map(&:to_s).join("\n\n"),
        matter_reference: case_record.clio_matter_id
      }.compact
    }
  end

  def related_party_operations
    case_record.related_parties.order(:created_at).map do |party|
      {
        action: party.clio_contact_id.present? ? "update_related_contact" : "find_or_create_related_contact",
        local_type: "RelatedParty",
        local_id: party.id,
        external_id: party.clio_contact_id,
        payload: {
          name: party.name,
          role: party.role,
          email: party.email,
          phone: party.phone,
          represented_status: party.represented_status,
          counsel_name: party.counsel_name,
          matter_reference: case_record.clio_matter_id
        }.compact
      }
    end
  end

  def task_operations
    case_record.case_tasks.order(:created_at).map do |task|
      {
        action: task.clio_task_id.present? ? "update_task" : "create_task",
        local_type: "CaseTask",
        local_id: task.id,
        external_id: task.clio_task_id,
        payload: {
          name: task.title,
          description: task.description,
          priority: task.priority,
          status: task.status,
          due_at: task.due_at&.iso8601,
          matter_reference: case_record.clio_matter_id
        }.compact
      }
    end
  end
end
