class AddRoleToAdminUsersAndRefundFieldsToPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :admin_users, :role, :integer, null: false, default: 0
    add_index :admin_users, :role

    add_column :payments, :refunded_amount, :decimal, precision: 10, scale: 2, null: false, default: 0
    add_column :payments, :refund_transaction_id, :string
    add_column :payments, :refunded_at, :datetime
    add_column :payments, :last_refund_reason, :string
  end
end
