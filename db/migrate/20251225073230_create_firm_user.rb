class CreateFirmUser < ActiveRecord::Migration[8.0]
  def change
    create_table :firm_users do |t|
      t.references :firm, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :role, null: false, default: 0  # e.g., 0: member, 1: admin

      t.timestamps
    end

    add_index :firm_users, [:firm_id, :user_id]
  end
end
