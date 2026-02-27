class CreatePayment3dsSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_3ds_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: true
      t.references :payment, null: false, foreign_key: true
      t.references :payment_method, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :callback_token, null: false
      t.string :spreedly_transaction_token
      t.string :challenge_url
      t.jsonb :raw_response, null: false, default: {}
      t.datetime :completed_at
      t.timestamps
    end

    add_index :payment_3ds_sessions, :callback_token, unique: true
    add_index :payment_3ds_sessions, :spreedly_transaction_token, unique: true
    add_index :payment_3ds_sessions, :status
  end
end


