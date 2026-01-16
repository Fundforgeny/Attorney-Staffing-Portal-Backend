class AddFirmIdToUsers < ActiveRecord::Migration[8.0]
  def change
    add_reference :users, :firm, null: true, foreign_key: true
  end
end
