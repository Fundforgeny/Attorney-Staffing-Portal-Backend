class CleanupPaymentMethodRelationships < ActiveRecord::Migration[8.0]
  def change
    remove_column :users, :payment_method_id, :integer
    remove_foreign_key :payment_methods, :users
    add_foreign_key :payment_methods, :users, on_delete: :cascade
  end
end
