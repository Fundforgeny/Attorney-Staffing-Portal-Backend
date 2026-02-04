class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :payments do |t|
      t.references :plan, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :payment_method, null: false, foreign_key: true
      t.integer :payment_type, default: 0  # down_payment, monthly_payment, one_time_payment
      t.decimal :payment_amount, precision: 10, scale: 2
      t.integer :status, default: 0  # pending, processing, succeeded, failed
      t.string :stripe_charge_id
      t.datetime :scheduled_at
      t.datetime :paid_at

      t.timestamps
    end
  end
end
