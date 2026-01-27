class AddCardDetailsToPaymentMethods < ActiveRecord::Migration[8.0]
  def change
    add_column :payment_methods, :card_number, :string
    add_column :payment_methods, :card_cvc, :string

    # Data migration: Move card details from vault_token to new columns
    reversible do |dir|
      dir.up do
        PaymentMethod.where.not(vault_token: nil).find_each do |payment_method|
          vault_token = payment_method.vault_token.to_s
          
          # Extract card number (assuming it's stored as plain number in vault_token)
          if vault_token.match?(/^\d+$/)
            payment_method.update_column(:card_number, vault_token)
          end
          
          # Note: CVC is typically not stored for security reasons
          # If it exists in vault_token, you would need to implement specific parsing logic
          # based on how it's stored in your system
        end
      end
      
      dir.down do
        # Optional: Move data back if needed
        PaymentMethod.where.not(card_number: nil).find_each do |payment_method|
          payment_method.update_column(:vault_token, payment_method.card_number)
        end
      end
    end
  end
end
