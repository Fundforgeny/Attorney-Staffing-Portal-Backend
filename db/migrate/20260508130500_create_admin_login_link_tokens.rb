class CreateAdminLoginLinkTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_login_link_tokens do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end

    add_index :admin_login_link_tokens, :token_digest, unique: true
    add_index :admin_login_link_tokens, :expires_at
    add_index :admin_login_link_tokens, :used_at
  end
end
