class AddSignedAtToAgreements < ActiveRecord::Migration[8.0]
  def change
    add_column :agreements, :signed_at, :datetime
  end
end
