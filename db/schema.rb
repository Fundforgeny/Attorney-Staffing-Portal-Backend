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

ActiveRecord::Schema[8.0].define(version: 2026_01_05_142400) do
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

  create_table "agreements", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "plan_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["created_by_id"], name: "index_cases_on_created_by_id"
    t.index ["firm_id"], name: "index_cases_on_firm_id"
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

  create_table "firm_users", force: :cascade do |t|
    t.bigint "firm_id", null: false
    t.bigint "user_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["firm_id", "user_id"], name: "index_firm_users_on_firm_id_and_user_id"
    t.index ["firm_id"], name: "index_firm_users_on_firm_id"
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
  end

  create_table "jwt_denylists", force: :cascade do |t|
    t.string "jti", null: false
    t.datetime "exp", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jti"], name: "index_jwt_denylists_on_jti"
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
    t.index ["stripe_payment_method_id"], name: "index_payment_methods_on_stripe_payment_method_id", unique: true
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
    t.index ["payment_method_id"], name: "index_payments_on_payment_method_id"
    t.index ["plan_id"], name: "index_payments_on_plan_id"
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
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_plans_on_user_id"
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
    t.integer "payment_method_id"
    t.string "verification_status"
    t.index ["user_type"], name: "index_users_on_user_type"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agreements", "plans"
  add_foreign_key "agreements", "users"
  add_foreign_key "attorney_profiles", "firms"
  add_foreign_key "attorney_profiles", "users"
  add_foreign_key "cases", "firms"
  add_foreign_key "cases", "users"
  add_foreign_key "cases", "users", column: "created_by_id"
  add_foreign_key "client_profiles", "firms"
  add_foreign_key "client_profiles", "users"
  add_foreign_key "firm_users", "firms"
  add_foreign_key "firm_users", "users"
  add_foreign_key "payment_methods", "users"
  add_foreign_key "payments", "payment_methods"
  add_foreign_key "payments", "plans"
  add_foreign_key "payments", "users"
  add_foreign_key "plans", "users"
end
