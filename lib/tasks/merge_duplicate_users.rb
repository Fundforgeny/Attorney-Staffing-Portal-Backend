# lib/tasks/merge_duplicate_users.rb
# Run with: bundle exec rails runner lib/tasks/merge_duplicate_users.rb
#
# Merges duplicate user records where the same email or phone appears more than once.
# Strategy: keep the oldest user (lowest ID) as canonical, reassign all plans/payments
# from duplicates to the canonical user, then delete duplicates.

puts "=== Duplicate User Merge Script ==="

# Find all duplicate emails
duplicate_emails = User.group(:email)
                       .having("COUNT(*) > 1")
                       .pluck(:email)

puts "Found #{duplicate_emails.count} duplicate email(s): #{duplicate_emails.inspect}"

duplicate_emails.each do |email|
  users = User.where(email: email).order(:id)
  canonical = users.first
  duplicates = users.where.not(id: canonical.id)

  puts "\nEmail: #{email}"
  puts "  Canonical user: ID=#{canonical.id}, name=#{canonical.full_name}"
  duplicates.each do |dup|
    puts "  Duplicate user: ID=#{dup.id}, name=#{dup.full_name}"

    # Reassign plans
    plan_count = Plan.where(user_id: dup.id).count
    Plan.where(user_id: dup.id).update_all(user_id: canonical.id)
    puts "    Reassigned #{plan_count} plan(s) to user #{canonical.id}"

    # Reassign payments
    payment_count = Payment.where(user_id: dup.id).count rescue 0
    Payment.where(user_id: dup.id).update_all(user_id: canonical.id) rescue nil
    puts "    Reassigned #{payment_count} payment(s) to user #{canonical.id}"

    # Reassign firm_users
    FirmUser.where(user_id: dup.id).each do |fu|
      existing = FirmUser.find_by(user_id: canonical.id, firm_id: fu.firm_id)
      if existing
        # Merge GHL IDs if missing on canonical
        existing.update(ghl_fund_forge_id: fu.ghl_fund_forge_id) if existing.ghl_fund_forge_id.blank? && fu.ghl_fund_forge_id.present?
        fu.destroy
      else
        fu.update(user_id: canonical.id)
      end
    end
    puts "    Merged firm_user associations"

    # Merge phone if canonical is missing it
    if canonical.phone.blank? && dup.phone.present?
      canonical.update_column(:phone, dup.phone)
      puts "    Copied phone #{dup.phone} to canonical user"
    end

    # Delete the duplicate
    dup.destroy
    puts "    Deleted duplicate user ID=#{dup.id}"
  end
end

# Also find duplicates by phone (where email differs)
duplicate_phones = User.where.not(phone: [nil, ""])
                       .group(:phone)
                       .having("COUNT(*) > 1")
                       .pluck(:phone)

puts "\nFound #{duplicate_phones.count} duplicate phone(s): #{duplicate_phones.inspect}"

duplicate_phones.each do |phone|
  users = User.where(phone: phone).order(:id)
  canonical = users.first
  duplicates = users.where.not(id: canonical.id)

  puts "\nPhone: #{phone}"
  puts "  Canonical user: ID=#{canonical.id}, email=#{canonical.email}"
  duplicates.each do |dup|
    puts "  Duplicate user: ID=#{dup.id}, email=#{dup.email}"

    plan_count = Plan.where(user_id: dup.id).count
    Plan.where(user_id: dup.id).update_all(user_id: canonical.id)
    puts "    Reassigned #{plan_count} plan(s)"

    FirmUser.where(user_id: dup.id).each do |fu|
      existing = FirmUser.find_by(user_id: canonical.id, firm_id: fu.firm_id)
      if existing
        existing.update(ghl_fund_forge_id: fu.ghl_fund_forge_id) if existing.ghl_fund_forge_id.blank? && fu.ghl_fund_forge_id.present?
        fu.destroy
      else
        fu.update(user_id: canonical.id)
      end
    end

    dup.destroy
    puts "    Deleted duplicate user ID=#{dup.id}"
  end
end

puts "\n=== Done ==="
puts "Verifying George Williams..."
george = User.find_by(email: "gwill2050@aol.com")
if george
  puts "George: ID=#{george.id}, plans=#{george.plans.count}, phone=#{george.phone}"
  george.plans.each { |p| puts "  Plan ID=#{p.id}, status=#{p.status}, name=#{p.name}" }
else
  puts "George not found by email gwill2050@aol.com"
end
