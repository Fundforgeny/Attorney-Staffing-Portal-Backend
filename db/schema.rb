# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_05_15_223000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_login_link_tokens", force: :cascade do |t|
    t.bigint "admin_user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_admin_login_link_tokens_on_admin_user_id"
    t.index ["expires_at"], name: "index_admin_login_link_tokens_on_expires_at"
    t.index ["token_digest"], name: "index_admin_login_link_tokens_on_token_digest", unique: true
    t.index ["used_at"], name: "index_admin_login_link_tokens_on_used_at"
  end

  create_table "admin_users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "contact_number", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role", default: 0, null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_admin_users_on_role"
  end

  create_table "agreements", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "plan_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "signed_at"
    t.index ["plan_id"], name: "index_agreements_on_plan_id"
    t.index ["user_id", "plan_id"], name: "index_agreements_on_user_id_and_plan_id", unique: true
    t.index ["user_id"], name: "index_agreements_on_user_id"
  end

  create_table "attorney_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "firm_id", null: false
    t.integer "ghl_contact_id"
    t.string "license_states", default: [], array: true
    t.string "source"
    t.string "tags", default: [], array: true
    t.string "practice_areas", default: [], array: true
    t.string "bar_number"
    t.string "jurisdiction"
    t.text "specialties"
    t.integer "years_experience"
    t.string "bio"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["firm_id"], name: "index_attorney_profiles_on_firm_id"
    t.index ["user_id"], name: "index_attorney_profiles_on_user_id"
  end

  create_table "attorneyprofiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "firm_id", null: false
    t.integer "ghl_contact_id"
    t.string "license_states", default: [], array: true
    t.string "source"
    t.string "tags", default: [], array: true
    t.string "practice_areas", default: [], array: true
    t.string "bar_number"
    t.string "jurisdiction"
    t.text "specialties"
    t.integer "years_experience"
    t.string "bio"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["firm_id"], name: "index_attorneyprofiles_on_firm_id"
    t.index ["user_id"], name: "index_attorneyprofiles_on_user_id"
  end

  create_table "case_intakes", force: :cascade do |t|
    t.bigint "case_id", null: false
    t.string "source", default: "manual", null: false
    t.string "ghl_contact_id"
    t.string "ghl_opportunity_id"
    t.string "review_status", default: "pending_review", null: false
    t.decimal "confidence", precision: 5, scale: 4
    t.text "transcript"
    t.jsonb "raw_payload", default: {}, null: false
    t.jsonb "ai_extraction", default: {}, null: false
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["case_id"], name: "index_case_intakes_on_case_id"
    t.index ["ghl_contact_id"], name: "index_case_intakes_on_ghl_contact_id"
    t.index ["ghl_opportunity_id"], name: "index_case_intakes_on_ghl_opportunity_id"
    t.index ["review_status"], name: "index_case_intakes_on_review_status"
    t.index ["reviewed_by_id"], name: "index_case_intakes_on_reviewed_by_id"
    t.index ["source"], name: "index_case_intakes_on_source"
  end

  create_table "case_tasks", force: :cascade do |t|
    t.bigint "case_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "priority", default: "normal", null: false
    t.string "status", default: "open", null: false
    t.string "source", default: "manual", null: false
    t.datetime "due_at"
    t.bigint "owner_id"
    t.string "clio_task_id"
    t.jsonb "custom_data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["case_id"], name: "index_case_tasks_on_case_id"
    t.index ["clio_task_id"], name: "index_case_tasks_on_clio_task_id"
    t.index ["owner_id"], name: "index_case_tasks_on_owner_id"
    t.index ["priority"], name: "index_case_tasks_on_priority"
    t.index ["source"], name: "index_case_tasks_on_source"
    t.index ["status"], name: "index_case_tasks_on_status"
  end

  create_table "cases", force: :cascade do |t|
    t.bigint "firm_id", null: false
    t.string "title", null: false
    t.text "description"
    t.jsonb "practice_areas", default: []
    t.string "jurisdiction"
    t.string "pay_type"
    t.decimal "pay_amount", precision: 15, scale: 2
    t.string "status"
    t.bigint "created_by_id", null: false
    t.string "clio_matter_id"
    t.string "matter_status"
    t.date "close_date"
    t.bigint "user_id"
    t.string "paralegal"
    t.jsonb "custom_data", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "client_user_id"
    t.date "open_date"
    t.string "county"
    t.string "zip_code"
    t.decimal "retainer_amount", precision: 15, scale: 2
    t.decimal "budget_amount", precision: 15, scale: 2
    t.string "staffing_status", default: "not_started", null: false
    t.index ["client_user_id"], name: "index_cases_on_client_user_id"
    t.index ["clio_matter_id"], name: "index_cases_on_clio_matter_id", unique: true, where: "(clio_matter_id IS NOT NULL)"
    t.index ["created_by_id"], name: "index_cases_on_created_by_id"
    t.index ["firm_id"], name: "index_cases_on_firm_id"
    t.index ["staffing_status"], name: "index_cases_on_staffing_status"
    t.index ["status"], name: "index_cases_on_status"
    t.index ["user_id"], name: "index_cases_on_user_id"
  end

  create_table "client_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "firm_id", null: false
    t.integer "ghl_contact_id"
    t.integer "work_hours_per_week"
    t.string "business_name"
    t.boolean "ever_been_convicted"
    t.string "service_number"
    t.boolean "is_employed"
    t.string "employer_name"
    t.text "additional_info"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["firm_id"], name: "index_client_profiles_on_firm_id"
    t.index ["user_id"], name: "index_client_profiles_on_user_id"
  end

  create_table "external_sync_records", force: :cascade do |t|
    t.string "provider", null: false
    t.string "syncable_type", null: false
    t.bigint "syncable_id", null: false
    t.string "external_id", null: false
    t.string "external_object_type", null: false
    t.string "status", default: "pending", null: false
    t.string "last_payload_hash"
    t.text "last_error"
    t.datetime "last_synced_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "external_object_type", "external_id"], name: "index_external_sync_records_on_provider_external_object", unique: true
    t.index ["status"], name: "index_external_sync_records_on_status"
    t.index ["syncable_type", "syncable_id"], name: "index_external_sync_records_on_syncable"
  end

  create_table "field_mappings", force: :cascade do |t|
    t.string "provider", null: false
    t.string "location_id"
    t.string "canonical_attribute", null: false
    t.string "external_field_id", null: false
    t.string "external_field_name"
    t.string "direction", default: "bidirectional", null: false
    t.string "transform"
    t.boolean "active", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_field_mappings_on_active"
    t.index ["provider", "location_id", "canonical_attribute"], name: "index_field_mappings_on_provider_location_attribute"
    t.index ["provider", "location_id", "external_field_id"], name: "index_field_mappings_on_provider_location_external_id", unique: true
  end

  create_table "firm_users", force: :cascade do |t|
    t.bigint "firm_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ghl_fund_forge_id"
    t.string "contact_id"
    t.index ["firm_id", "user_id"], name: "index_firm_users_on_firm_id_and_user_id"
    t.index ["firm_id"], name: "index_firm_users_on_firm_id"
    t.index ["ghl_fund_forge_id"], name: "index_firm_users_on_ghl_fund_forge_id"
    t.index ["user_id"], name: "index_firm_users_on_user_id"
  end

  create_table "firms", force: :cascade do |t|
    t.string "name", null: false
    t.string "logo"
    t.string "primary_color"
    t.string "secondary_color"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "location_id"
    t.string "ghl_api_key"
  end

  create_table "grace_week_requests", force: :cascade do |t|
    t.bigint "plan_id", null: false
    t.bigint "user_id", null: false
    t.bigint "payment_id", null: false
    t.integer "status", default: 0, null: false
    t.text "reason"
    t.text "admin_note"
    t.decimal "half_amount", precision: 10, scale: 2
    t.date "first_half_due"
    t.date "second_half_due"
    t.integer "halves_paid", default: 0
    t.datetime "approved_at"
    t.datetime "denied_at"
    t.datetime "requested_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_id"], name: "index_grace_week_requests_on_payment_id"
    t.index ["plan_id", "status"], name: "index_grace_week_requests_on_plan_id_and_status"
    t.index ["plan_id"], name: "index_grace_week_requests_on_plan_id"
    t.index ["status"], name: "index_grace_week_requests_on_status"
    t.index ["user_id"], name: "index_grace_week_requests_on_user_id"
  end

  create_table "jwt_denylists", force: :cascade do |t|
    t.string "jti", null: false
    t.datetime "exp", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jti"], name: "index_jwt_denylists_on_jti"
  end

  create_table "login_link_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_login_link_tokens_on_expires_at"
    t.index ["token_digest"], name: "index_login_link_tokens_on_token_digest", unique: true
    t.index ["used_at"], name: "index_login_link_tokens_on_used_at"
    t.index ["user_id"], name: "index_login_link_tokens_on_user_id"
  end

  create_table "payment_3ds_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "plan_id", null: false
    t.bigint "payment_id", null: false
    t.bigint "payment_method_id", null: false
    t.string "status", default: "pending", null: false
    t.string "callback_token", null: false
    t.string "spreedly_transaction_token"
    t.string "challenge_url"
    t.jsonb "raw_response", default: {}, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["callback_token"], name: "index_payment_3ds_sessions_on_callback_token", unique: true
    t.index ["payment_id"], name: "index_payment_3ds_sessions_on_payment_id"
    t.index ["payment_method_id"], name: "index_payment_3ds_sessions_on_payment_method_id"
    t.index ["plan_id"], name: "index_payment_3ds_sessions_on_plan_id"
    t.index ["spreedly_transaction_token"], name: "index_payment_3ds_sessions_on_spreedly_transaction_token", unique: true
    t.index ["status"], name: "index_payment_3ds_sessions_on_status"
    t.index ["user_id"], name: "index_payment_3ds_sessions_on_user_id"
  end

  create_table "payment_methods", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "provider", default: "stripe"
    t.string "stripe_payment_method_id"
    t.string "vault_token"
    t.string "last4"
    t.string "card_brand"
    t.integer "exp_month"
    t.integer "exp_year"
    t.string "cardholder_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "card_number"
    t.string "card_cvc"
    t.boolean "is_default", default: false, null: false
    t.datetime "spreedly_redacted_at"
    t.datetime "last_updated_via_spreedly_at"
    t.datetime "account_updater_checked_at"
    t.datetime "account_updater_updated_at"
    t.datetime "archived_at"
    t.index ["archived_at"], name: "index_payment_methods_on_archived_at"
    t.index ["stripe_payment_method_id"], name: "index_payment_methods_on_stripe_payment_method_id", unique: true
    t.index ["user_id", "is_default"], name: "index_payment_methods_on_user_default", where: "(is_default = true)"
    t.index ["user_id", "vault_token"], name: "idx_payment_methods_user_vault_token", where: "(vault_token IS NOT NULL)"
    t.index ["user_id"], name: "index_payment_methods_on_user_id"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "plan_id"
    t.bigint "user_id", null: false
    t.bigint "payment_method_id", null: false
    t.integer "payment_type", default: 0
    t.decimal "payment_amount", precision: 10, scale: 2
    t.integer "status", default: 0
    t.string "charge_id"
    t.datetime "scheduled_at"
    t.datetime "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "total_payment_including_fee"
    t.decimal "transaction_fee"
    t.integer "retry_count", default: 0, null: false
    t.datetime "last_attempt_at"
    t.datetime "next_retry_at"
    t.string "decline_reason"
    t.boolean "needs_new_card", default: false, null: false
    t.bigint "grace_week_request_id"
    t.boolean "disputed", default: false, null: false
    t.string "chargeflow_alert_id"
    t.string "chargeflow_dispute_id"
    t.datetime "disputed_at"
    t.boolean "chargeflow_recovery", default: false, null: false
    t.string "processor_transaction_id"
    t.decimal "refunded_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.string "refund_transaction_id"
    t.datetime "refunded_at"
    t.string "last_refund_reason"
    t.index ["chargeflow_alert_id"], name: "index_payments_on_chargeflow_alert_id"
    t.index ["chargeflow_dispute_id"], name: "index_payments_on_chargeflow_dispute_id"
    t.index ["chargeflow_recovery"], name: "index_payments_on_chargeflow_recovery"
    t.index ["disputed"], name: "index_payments_on_disputed"
    t.index ["grace_week_request_id"], name: "index_payments_on_grace_week_request_id"
    t.index ["needs_new_card"], name: "index_payments_on_needs_new_card"
    t.index ["next_retry_at"], name: "index_payments_on_next_retry_at"
    t.index ["payment_method_id"], name: "index_payments_on_payment_method_id"
    t.index ["plan_id"], name: "index_payments_on_plan_id"
    t.index ["processor_transaction_id"], name: "index_payments_on_processor_transaction_id"
    t.index ["user_id"], name: "index_payments_on_user_id"
  end

  create_table "plans", force: :cascade do |t|
    t.string "name", null: false
    t.integer "duration"
    t.decimal "total_payment", precision: 10, scale: 2, null: false
    t.decimal "total_interest_amount", precision: 10, scale: 2
    t.decimal "monthly_payment", precision: 10, scale: 2, null: false
    t.decimal "monthly_interest_amount", precision: 10, scale: 2
    t.decimal "down_payment", precision: 10, scale: 2, null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "magic_link_token"
    t.string "checkout_session_id", null: false
    t.datetime "next_payment_at"
    t.decimal "chargeflow_alert_fee", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["checkout_session_id"], name: "index_plans_on_checkout_session_id", unique: true
    t.index ["status"], name: "index_plans_on_status"
    t.index ["user_id"], name: "index_plans_on_user_id"
  end

  create_table "related_parties", force: :cascade do |t|
    t.bigint "case_id", null: false
    t.string "name", null: false
    t.string "role", default: "unknown", null: false
    t.string "email"
    t.string "phone"
    t.string "represented_status"
    t.string "counsel_name"
    t.string "counsel_email"
    t.string "counsel_phone"
    t.string "clio_contact_id"
    t.jsonb "custom_data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["case_id"], name: "index_related_parties_on_case_id"
    t.index ["clio_contact_id"], name: "index_related_parties_on_clio_contact_id"
    t.index ["role"], name: "index_related_parties_on_role"
  end

  create_table "staffing_requirements", force: :cascade do |t|
    t.bigint "case_id", null: false
    t.string "status", default: "draft", null: false
    t.string "urgency", default: "standard", null: false
    t.string "required_license_states", default: [], null: false, array: true
    t.string "federal_court_admissions", default: [], null: false, array: true
    t.jsonb "practice_areas", default: [], null: false
    t.string "county"
    t.string "zip_code"
    t.boolean "residency_required", default: true, null: false
    t.integer "target_interview_count", default: 5, null: false
    t.jsonb "custom_data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["case_id"], name: "index_staffing_requirements_on_case_id"
    t.index ["federal_court_admissions"], name: "index_staffing_requirements_on_federal_court_admissions", using: :gin
    t.index ["required_license_states"], name: "index_staffing_requirements_on_required_license_states", using: :gin
    t.index ["status"], name: "index_staffing_requirements_on_status"
    t.index ["urgency"], name: "index_staffing_requirements_on_urgency"
  end

  create_table "users", force: :cascade do |t|
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.string "first_name"
    t.string "last_name"
    t.string "email", default: "", null: false
    t.string "phone"
    t.date "dob"
    t.text "address_street"
    t.string "city"
    t.string "state"
    t.string "postal_code"
    t.string "country", default: "United States"
    t.string "time_zone", default: "GMT-05:00 US/Eastern (EST)"
    t.string "contact_source"
    t.boolean "is_verfied", default: true
    t.integer "annual_salary"
    t.integer "user_type", default: 0, null: false
    t.string "stripe_verification_status"
    t.string "stripe_verification_session_id"
    t.bigint "firm_id"
    t.string "stripe_customer_id"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["firm_id"], name: "index_users_on_firm_id"
    t.index ["user_type"], name: "index_users_on_user_type"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "admin_login_link_tokens", "admin_users"
  add_foreign_key "agreements", "plans"
  add_foreign_key "agreements", "users"
  add_foreign_key "attorney_profiles", "firms"
  add_foreign_key "attorney_profiles", "users"
  add_foreign_key "case_intakes", "cases"
  add_foreign_key "case_intakes", "users", column: "reviewed_by_id"
  add_foreign_key "case_tasks", "cases"
  add_foreign_key "case_tasks", "users", column: "owner_id"
  add_foreign_key "cases", "firms"
  add_foreign_key "cases", "users"
  add_foreign_key "cases", "users", column: "client_user_id"
  add_foreign_key "cases", "users", column: "created_by_id"
  add_foreign_key "client_profiles", "firms"
  add_foreign_key "client_profiles", "users"
  add_foreign_key "firm_users", "firms"
  add_foreign_key "firm_users", "users"
  add_foreign_key "grace_week_requests", "payments"
  add_foreign_key "grace_week_requests", "plans"
  add_foreign_key "grace_week_requests", "users"
  add_foreign_key "login_link_tokens", "users"
  add_foreign_key "payment_3ds_sessions", "payment_methods"
  add_foreign_key "payment_3ds_sessions", "payments"
  add_foreign_key "payment_3ds_sessions", "plans"
  add_foreign_key "payment_3ds_sessions", "users"
  add_foreign_key "payment_methods", "users", on_delete: :cascade
  add_foreign_key "payments", "payment_methods"
  add_foreign_key "payments", "plans"
  add_foreign_key "payments", "users"
  add_foreign_key "plans", "users"
  add_foreign_key "related_parties", "cases"
  add_foreign_key "staffing_requirements", "cases"
  add_foreign_key "users", "firms"
end
