class AddRetryFieldsToPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :payments, :retry_count,      :integer,  default: 0, null: false
    add_column :payments, :last_attempt_at,  :datetime
    add_column :payments, :next_retry_at,    :datetime
    add_column :payments, :decline_reason,   :string
    add_column :payments, :needs_new_card,   :boolean,  default: false, null: false

    add_index :payments, :next_retry_at
    add_index :payments, :needs_new_card
  end
end
