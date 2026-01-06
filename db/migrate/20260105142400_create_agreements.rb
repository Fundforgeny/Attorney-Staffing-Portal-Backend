class CreateAgreements < ActiveRecord::Migration[8.0]
  def change
    create_table :agreements do |t|
      t.references :user, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: true
      
      t.timestamps
    end

    add_index :agreements, [:user_id, :plan_id], unique: true
  end
end
