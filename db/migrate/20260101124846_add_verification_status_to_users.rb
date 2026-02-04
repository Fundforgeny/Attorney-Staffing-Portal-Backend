class AddVerificationStatusToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :verification_status, :string
  end
end
