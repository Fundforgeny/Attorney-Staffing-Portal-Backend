class RemoveMagicLinkTokenFromUsers < ActiveRecord::Migration[8.0]
  def change
    remove_column :users, :magic_link_token, :string
  end
end
