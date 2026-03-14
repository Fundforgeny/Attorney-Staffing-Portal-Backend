class AllowDuplicateVaultTokensPerUser < ActiveRecord::Migration[8.0]
  def up
    remove_index :payment_methods, name: "idx_payment_methods_user_vault_token", if_exists: true
    add_index :payment_methods, [ :user_id, :vault_token ], where: "vault_token IS NOT NULL", name: "idx_payment_methods_user_vault_token"
  end

  def down
    remove_index :payment_methods, name: "idx_payment_methods_user_vault_token", if_exists: true
    add_index :payment_methods, [ :user_id, :vault_token ], unique: true, where: "vault_token IS NOT NULL", name: "idx_payment_methods_user_vault_token"
  end
end
