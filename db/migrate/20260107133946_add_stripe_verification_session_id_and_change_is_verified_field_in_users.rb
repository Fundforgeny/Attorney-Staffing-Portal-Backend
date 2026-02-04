class AddStripeVerificationSessionIdAndChangeIsVerifiedFieldInUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :stripe_verification_session_id, :string

    rename_column :users, :verification_status, :stripe_verification_status
  end
end
