class CreateClientProfile < ActiveRecord::Migration[8.0]
  def change
    create_table :client_profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.references :firm, null: false, foreign_key: true

      t.integer :ghl_contact_id
      t.integer   :work_hours_per_week
      t.string :business_name
      t.boolean :ever_been_convicted
      t.string :service_number
      t.boolean :is_employed
      t.string :employer_name
      t.text :additional_info

      t.timestamps
    end
  end
end
