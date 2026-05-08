class AddArchivedAtToPaymentMethods < ActiveRecord::Migration[8.0]
  def change
    add_column :payment_methods, :archived_at, :datetime
    add_index :payment_methods, :archived_at
  end
end
