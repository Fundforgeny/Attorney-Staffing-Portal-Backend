# lib/tasks/migrate_payment_card_details.rake
namespace :payment_methods do
  desc "Extract card details from vault_token JSON and save to dedicated columns"
  task migrate_card_details: :environment do
    puts "Starting migration of card details from vault_token..."
    
    migrated_count = 0
    error_count = 0
    
    PaymentMethod.where.not(vault_token: nil).find_each do |payment_method|
      begin
        vault_token = payment_method.vault_token.to_s.strip
        
        # Skip if vault_token is already a plain number (already migrated)
        if vault_token.match?(/^\d+$/)
          puts "Skipping PaymentMethod ##{payment_method.id} - already migrated"
          next
        end
        
        # Parse JSON if it looks like JSON format
        if vault_token.include?('"number"') || vault_token.include?('number')
          parsed_data = parse_vault_token(vault_token)
          
          if parsed_data.present?
            payment_method.update_columns(
              card_number: parsed_data[:number],
              card_cvc: parsed_data[:cvc]
            )
            migrated_count += 1
            puts "Migrated PaymentMethod ##{payment_method.id}: #{parsed_data[:number]&.to_s&.first(4)}****#{parsed_data[:number]&.to_s&.last(4)}"
          else
            puts "Could not parse vault_token for PaymentMethod ##{payment_method.id}"
            error_count += 1
          end
        else
          puts "Skipping PaymentMethod ##{payment_method.id} - not JSON format"
        end
        
      rescue => e
        puts "Error processing PaymentMethod ##{payment_method.id}: #{e.message}"
        error_count += 1
      end
    end
    
    puts "\nMigration completed!"
    puts "Successfully migrated: #{migrated_count} payment methods"
    puts "Errors encountered: #{error_count} payment methods"
  end
  
  private
  
  def parse_vault_token(vault_token)
    # Try to parse as JSON
    if vault_token.start_with?('{') && vault_token.end_with?('}')
      begin
        data = JSON.parse(vault_token)
        return {
          number: data['number'],
          cvc: data['cvc']
        }
      rescue JSON::ParserError
        # If JSON parsing fails, try regex extraction
        return extract_with_regex(vault_token)
      end
    else
      # Try regex extraction for malformed JSON
      return extract_with_regex(vault_token)
    end
  end
  
  def extract_with_regex(vault_token)
    result = {}
    
    # Extract number
    number_match = vault_token.match(/"number"\s*=>\s*"([^"]+)"/) || 
                   vault_token.match(/"number"\s*:\s*"([^"]+)"/) ||
                   vault_token.match(/number\s*=>\s*([^\s,}]+)/) ||
                   vault_token.match(/number\s*:\s*([^\s,}]+)/)
    
    result[:number] = number_match[1] if number_match
    
    # Extract cvc
    cvc_match = vault_token.match(/"cvc"\s*=>\s*"([^"]+)"/) || 
                vault_token.match(/"cvc"\s*:\s*"([^"]+)"/) ||
                vault_token.match(/cvc\s*=>\s*([^\s,}]+)/) ||
                vault_token.match(/cvc\s*:\s*([^\s,}]+)/)
    
    result[:cvc] = cvc_match[1] if cvc_match
    
    result.present? ? result : nil
  end
end
