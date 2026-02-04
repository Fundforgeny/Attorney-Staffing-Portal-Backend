class AddPaymentMethodIdToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :payment_method_id, :integer
  end
end
