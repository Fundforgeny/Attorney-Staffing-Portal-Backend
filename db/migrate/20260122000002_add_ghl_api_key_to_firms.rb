class AddGhlApiKeyToFirms < ActiveRecord::Migration[8.0]
  def change
    add_column :firms, :ghl_api_key, :string
  end
end
