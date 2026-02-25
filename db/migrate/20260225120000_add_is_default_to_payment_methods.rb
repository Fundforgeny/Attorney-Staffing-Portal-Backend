class AddIsDefaultToPaymentMethods < ActiveRecord::Migration[8.0]
  def up
    add_column :payment_methods, :is_default, :boolean, default: false, null: false unless column_exists?(:payment_methods, :is_default)
    add_index :payment_methods, [ :user_id, :is_default ], where: "is_default = true", name: "index_payment_methods_on_user_default" unless index_exists?(:payment_methods, [ :user_id, :is_default ], name: "index_payment_methods_on_user_default")

    execute <<~SQL
      UPDATE payment_methods pm
      SET is_default = true
      WHERE pm.id IN (
        SELECT DISTINCT ON (user_id) id
        FROM payment_methods
        ORDER BY user_id, created_at DESC
      )
    SQL
  end

  def down
    remove_index :payment_methods, name: "index_payment_methods_on_user_default" if index_exists?(:payment_methods, [ :user_id, :is_default ], name: "index_payment_methods_on_user_default")
    remove_column :payment_methods, :is_default if column_exists?(:payment_methods, :is_default)
  end
end

