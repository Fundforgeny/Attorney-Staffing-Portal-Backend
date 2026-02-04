class RenameStripeChargeIdToChargeIdInPayments < ActiveRecord::Migration[8.0]
  def change
    rename_column :payments, :stripe_charge_id, :charge_id
  end
end
