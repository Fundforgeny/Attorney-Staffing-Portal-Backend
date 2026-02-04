class AddLocationIdToFirms < ActiveRecord::Migration[8.0]
  def change
    add_column :firms, :location_id, :string
  end
end
