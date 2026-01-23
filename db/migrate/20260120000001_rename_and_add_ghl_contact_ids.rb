class RenameAndAddGhlContactIds < ActiveRecord::Migration[8.0]
  def change
    # First, rename existing ghl_contact_id to ghl_fund_forge_id
    rename_column :users, :ghl_contact_id, :ghl_fund_forge_id
    
    # Then add new ghl_ironclad_id column
    add_column :users, :ghl_ironclad_id, :string
    
    # Add index for the new column
    add_index :users, :ghl_ironclad_id
  end
end
