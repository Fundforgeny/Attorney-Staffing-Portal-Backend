class AddTimestampsToUsers < ActiveRecord::Migration[8.0]
  def up
    # Add created_at and updated_at if they don't exist
    unless column_exists?(:users, :created_at)
      add_column :users, :created_at, :datetime, null: false, default: -> { "NOW()" }
    end
    unless column_exists?(:users, :updated_at)
      add_column :users, :updated_at, :datetime, null: false, default: -> { "NOW()" }
    end
  end

  def down
    remove_column :users, :created_at, if_exists: true
    remove_column :users, :updated_at, if_exists: true
  end
end
