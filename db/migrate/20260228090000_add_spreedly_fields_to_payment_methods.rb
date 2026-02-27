class AddSpreedlyFieldsToPaymentMethods < ActiveRecord::Migration[8.0]
  def up
    add_column :payment_methods, :spreedly_redacted_at, :datetime
    add_column :payment_methods, :last_updated_via_spreedly_at, :datetime

    # Legacy rows may contain duplicated or non-tokenized card payloads in vault_token.
    # Clean those before adding a unique index on real Spreedly tokens.
    execute <<~SQL.squish
      UPDATE payment_methods
      SET vault_token = NULL
      WHERE vault_token IS NOT NULL
        AND (
          trim(vault_token) = ''
          OR vault_token LIKE '{%'
        );
    SQL

    execute <<~SQL.squish
      WITH ranked AS (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY user_id, vault_token
                 ORDER BY updated_at DESC NULLS LAST, id DESC
               ) AS row_num
        FROM payment_methods
        WHERE vault_token IS NOT NULL
      )
      UPDATE payment_methods pm
      SET vault_token = NULL
      FROM ranked r
      WHERE pm.id = r.id
        AND r.row_num > 1;
    SQL

    add_index :payment_methods, [ :user_id, :vault_token ], unique: true, where: "vault_token IS NOT NULL", name: "idx_payment_methods_user_vault_token"
  end

  def down
    remove_index :payment_methods, name: "idx_payment_methods_user_vault_token", if_exists: true
    remove_column :payment_methods, :last_updated_via_spreedly_at, if_exists: true
    remove_column :payment_methods, :spreedly_redacted_at, if_exists: true
  end
end


