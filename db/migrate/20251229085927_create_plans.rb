class CreatePlans < ActiveRecord::Migration[8.0]
  def change
    create_table :plans do |t|
      t.string :name, null: false
      t.integer :duration
      t.decimal :total_payment, null: false, precision: 10, scale: 2
      t.decimal :total_interest_amount, precision: 10, scale: 2
      t.decimal :monthly_payment, null: false, precision: 10, scale: 2
      t.decimal :monthly_interest_amount, precision: 10, scale: 2
      t.decimal :down_payment, null: false, precision: 10, scale: 2
      t.integer :status, default: 0

      t.timestamps
    end
  end
end
