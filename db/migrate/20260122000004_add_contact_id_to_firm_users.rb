class AddContactIdToFirmUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :firm_users, :contact_id, :string
    remove_column :firm_users, :ghl_ironclad_id
    remove_column :firm_users, :tital_law_id
  end
end
