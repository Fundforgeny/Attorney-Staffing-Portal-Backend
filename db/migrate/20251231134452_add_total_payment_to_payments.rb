class AddTotalPaymentToPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :payments, :total_payment_including_fee, :decimal
    add_column :payments, :transaction_fee, :decimal
  end
end
