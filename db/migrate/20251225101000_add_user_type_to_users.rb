class AddUserTypeToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :user_type, :integer, null: false, default: 0
    add_index :users, :user_type
  end
end
