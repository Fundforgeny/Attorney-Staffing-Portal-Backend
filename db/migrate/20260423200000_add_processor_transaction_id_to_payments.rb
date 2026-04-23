class AddProcessorTransactionIdToPayments < ActiveRecord::Migration[7.1]
  def change
    add_column :payments, :processor_transaction_id, :string
    add_index  :payments, :processor_transaction_id, name: "index_payments_on_processor_transaction_id"
  end
end
