class AddStaffingMatterFoundation < ActiveRecord::Migration[8.0]
  def change
    change_table :cases do |t|
      t.references :client_user, null: true, foreign_key: { to_table: :users }
      t.date :open_date
      t.string :county
      t.string :zip_code
      t.decimal :retainer_amount, precision: 15, scale: 2
      t.decimal :budget_amount, precision: 15, scale: 2
      t.string :staffing_status, null: false, default: "not_started"
    end

    add_index :cases, :clio_matter_id, unique: true, where: "clio_matter_id IS NOT NULL"
    add_index :cases, :staffing_status

    create_table :case_intakes do |t|
      t.references :case, null: false, foreign_key: true
      t.string :source, null: false, default: "manual"
      t.string :ghl_contact_id
      t.string :ghl_opportunity_id
      t.string :review_status, null: false, default: "pending_review"
      t.decimal :confidence, precision: 5, scale: 4
      t.text :transcript
      t.jsonb :raw_payload, null: false, default: {}
      t.jsonb :ai_extraction, null: false, default: {}
      t.references :reviewed_by, null: true, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.timestamps
    end

    add_index :case_intakes, :source
    add_index :case_intakes, :review_status
    add_index :case_intakes, :ghl_contact_id
    add_index :case_intakes, :ghl_opportunity_id

    create_table :related_parties do |t|
      t.references :case, null: false, foreign_key: true
      t.string :name, null: false
      t.string :role, null: false, default: "unknown"
      t.string :email
      t.string :phone
      t.string :represented_status
      t.string :counsel_name
      t.string :counsel_email
      t.string :counsel_phone
      t.string :clio_contact_id
      t.jsonb :custom_data, null: false, default: {}
      t.timestamps
    end

    add_index :related_parties, :role
    add_index :related_parties, :clio_contact_id

    create_table :case_tasks do |t|
      t.references :case, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :priority, null: false, default: "normal"
      t.string :status, null: false, default: "open"
      t.string :source, null: false, default: "manual"
      t.datetime :due_at
      t.references :owner, null: true, foreign_key: { to_table: :users }
      t.string :clio_task_id
      t.jsonb :custom_data, null: false, default: {}
      t.timestamps
    end

    add_index :case_tasks, :status
    add_index :case_tasks, :priority
    add_index :case_tasks, :source
    add_index :case_tasks, :clio_task_id

    create_table :staffing_requirements do |t|
      t.references :case, null: false, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.string :urgency, null: false, default: "standard"
      t.string :required_license_states, null: false, default: [], array: true
      t.string :federal_court_admissions, null: false, default: [], array: true
      t.jsonb :practice_areas, null: false, default: []
      t.string :county
      t.string :zip_code
      t.boolean :residency_required, null: false, default: true
      t.integer :target_interview_count, null: false, default: 5
      t.jsonb :custom_data, null: false, default: {}
      t.timestamps
    end

    add_index :staffing_requirements, :status
    add_index :staffing_requirements, :urgency
    add_index :staffing_requirements, :required_license_states, using: :gin
    add_index :staffing_requirements, :federal_court_admissions, using: :gin

    create_table :field_mappings do |t|
      t.string :provider, null: false
      t.string :location_id
      t.string :canonical_attribute, null: false
      t.string :external_field_id, null: false
      t.string :external_field_name
      t.string :direction, null: false, default: "bidirectional"
      t.string :transform
      t.boolean :active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :field_mappings, [:provider, :location_id, :canonical_attribute], name: "index_field_mappings_on_provider_location_attribute"
    add_index :field_mappings, [:provider, :location_id, :external_field_id], unique: true, name: "index_field_mappings_on_provider_location_external_id"
    add_index :field_mappings, :active

    create_table :external_sync_records do |t|
      t.string :provider, null: false
      t.string :syncable_type, null: false
      t.bigint :syncable_id, null: false
      t.string :external_id, null: false
      t.string :external_object_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :last_payload_hash
      t.text :last_error
      t.datetime :last_synced_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :external_sync_records, [:syncable_type, :syncable_id], name: "index_external_sync_records_on_syncable"
    add_index :external_sync_records, [:provider, :external_object_type, :external_id], unique: true, name: "index_external_sync_records_on_provider_external_object"
    add_index :external_sync_records, :status
  end
end
