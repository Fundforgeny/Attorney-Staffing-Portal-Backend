class AddAccountUpdaterFieldsToPaymentMethods < ActiveRecord::Migration[8.0]
  def change
    add_column :payment_methods, :account_updater_checked_at, :datetime
    add_column :payment_methods, :account_updater_updated_at, :datetime
    # spreedly_redacted_at and last_updated_via_spreedly_at already added in 20260228090000
  end
end
