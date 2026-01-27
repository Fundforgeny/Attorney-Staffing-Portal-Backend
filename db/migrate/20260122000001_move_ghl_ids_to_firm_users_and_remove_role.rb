class MoveGhlIdsToFirmUsersAndRemoveRole < ActiveRecord::Migration[8.0]
  def change
    # Add new columns to firm_users table
    add_column :firm_users, :ghl_fund_forge_id, :string
    add_column :firm_users, :ghl_ironclad_id, :string
    add_column :firm_users, :tital_law_id, :string
    
    # Add indexes for the new columns
    add_index :firm_users, :ghl_fund_forge_id
    add_index :firm_users, :ghl_ironclad_id
    add_index :firm_users, :tital_law_id
    
    # Migrate data from users to firm_users
    execute <<-SQL
      UPDATE firm_users 
      SET ghl_fund_forge_id = users.ghl_fund_forge_id,
          ghl_ironclad_id = users.ghl_ironclad_id
      FROM users 
      WHERE firm_users.user_id = users.id
    SQL
    
    # Remove columns from users table
    remove_column :users, :ghl_fund_forge_id
    remove_column :users, :ghl_ironclad_id
    
    # Remove role column from firm_users table
    remove_column :firm_users, :role
  end
end
