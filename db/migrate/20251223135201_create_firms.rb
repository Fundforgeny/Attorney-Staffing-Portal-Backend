class CreateFirms < ActiveRecord::Migration[8.0]
  def change
    create_table :firms do |t|
      t.string :name, null: false
      t.string :logo
      t.string :primary_color
      t.string :secondary_color
      t.text :description

      t.timestamps
    end
  end
end
