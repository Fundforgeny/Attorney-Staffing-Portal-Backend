class CreatePaymentMethods < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_methods do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, default: "stripe"
      t.string :stripe_payment_method_id, index: { unique: true }
      t.string :vault_token
      t.string :last4
      t.string :card_brand
      t.integer :exp_month
      t.integer :exp_year
      t.string :cardholder_name

      t.timestamps
    end
  end
end
