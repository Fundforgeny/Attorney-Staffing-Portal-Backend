class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :encrypted_password, null: false, default: ""

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      ## Trackable (optional but recommended)
      t.integer  :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      ## Confirmable (optional – remove if not using email confirmation)
      t.string   :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string   :unconfirmed_email

      # Remaining Columns
      t.string  :first_name
      t.string  :last_name
      t.string  :email, null: false, default: ""
      t.string  :phone
      t.date    :dob
      t.text    :address_street
      t.string  :city
      t.string  :state
      t.string  :postal_code
      t.string  :country, default: 'United States'
      t.string  :time_zone, default: 'GMT-05:00 US/Eastern (EST)'
      t.string :contact_source
      t.boolean :is_verfied, default: true
      t.integer :annual_salary
    end
  end
end
