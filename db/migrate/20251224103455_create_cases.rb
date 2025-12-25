class CreateCases < ActiveRecord::Migration[8.0]
  def change
    create_table :cases do |t|
      t.references :firm, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.jsonb :practice_areas, default: []
      t.string :jurisdiction
      t.string :pay_type
      t.decimal :pay_amount, precision: 15, scale: 2
      t.string :status
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :clio_matter_id
      t.string :matter_status
      t.date :close_date
      t.references :user, null: true, foreign_key: true
      t.string :paralegal

      t.jsonb :custom_data, default: {}

      t.timestamps
    end

    add_index :cases, :status
  end
end
