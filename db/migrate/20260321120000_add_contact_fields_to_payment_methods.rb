class AddContactFieldsToPaymentMethods < ActiveRecord::Migration[8.0]
  def change
    add_column :payment_methods, :billing_email, :string unless column_exists?(:payment_methods, :billing_email)
    add_column :payment_methods, :billing_phone, :string unless column_exists?(:payment_methods, :billing_phone)
    add_column :payment_methods, :billing_address1, :string unless column_exists?(:payment_methods, :billing_address1)
    add_column :payment_methods, :billing_address2, :string unless column_exists?(:payment_methods, :billing_address2)
    add_column :payment_methods, :billing_city, :string unless column_exists?(:payment_methods, :billing_city)
    add_column :payment_methods, :billing_state, :string unless column_exists?(:payment_methods, :billing_state)
    add_column :payment_methods, :billing_zip, :string unless column_exists?(:payment_methods, :billing_zip)
    add_column :payment_methods, :billing_country, :string unless column_exists?(:payment_methods, :billing_country)
  end
end
