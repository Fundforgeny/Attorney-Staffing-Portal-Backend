class CreateAttorneyProfile < ActiveRecord::Migration[8.0]
  def change
    create_table :attorney_profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.references :firm, null: false, foreign_key: true

      t.integer :ghl_contact_id
      t.string :license_states, array: true, default: []
      t.string :source
      t.string :tags, array: true, default: []
      t.string :practice_areas, array: true, default: []
      t.string :bar_number
      t.string :jurisdiction
      t.text   :specialties
      t.integer :years_experience
      t.string :bio

      t.timestamps
    end
  end
end
