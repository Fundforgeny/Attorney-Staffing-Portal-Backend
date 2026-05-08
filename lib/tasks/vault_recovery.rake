# frozen_string_literal: true

# Vault recovery tasks.
#
# Safe report/validation tasks:
#   bundle exec rails vault:recovery_report
#   bundle exec rails vault:validate_tokens
#   bundle exec rails vault:validate_tokens SCOPE=all
#   bundle exec rails vault:validate_tokens SCOPE=redacted_local
#
# Autopilot safe-fix task:
#   bundle exec rails vault:autopilot
#   bundle exec rails vault:autopilot APPLY=false
#
# Controlled overdue charge queue:
#   bundle exec rails vault:charge_overdue APPLY=false
#   bundle exec rails vault:charge_overdue APPLY=true
#
# Controlled restore task for one known recovered token:
#   bundle exec rails vault:restore_token PAYMENT_METHOD_ID=123 VAULT_TOKEN=01ABC... REACTIVATE=false
#
# Autopilot does not charge cards. charge_overdue queues real charge jobs, but
# only for eligible active/unpaid overdue plans with usable non-archived,
# non-redacted local vault tokens.
#
namespace :vault do
  desc "Print a read-only vault recovery report for payment methods and payments needing cards"
  task recovery_report: :environment do
    VaultRecoveryReporter.new.print_report
  end

  desc "Validate local Spreedly vault tokens without charging or modifying records"
  task validate_tokens: :environment do
    scope = ENV.fetch("SCOPE", "active_targets")
    VaultTokenValidator.new(scope: scope).print_report
  end

  desc "Run all-in-one vault recovery autopilot; does safe local fixes only"
  task autopilot: :environment do
    VaultRecoveryAutopilot.new(apply: ENV.fetch("APPLY", "true")).call
  end

  desc "Queue one controlled overdue charge attempt per eligible active/unpaid plan"
  task charge_overdue: :environment do
    OneTimeOverdueChargeRun.new(apply: ENV.fetch("APPLY", "false")).call
  end

  desc "Restore one recovered vault token to one PaymentMethod after Spreedly validation"
  task restore_token: :environment do
    VaultTokenRestorer.new(
      payment_method_id: ENV["PAYMENT_METHOD_ID"],
      vault_token: ENV["VAULT_TOKEN"],
      reactivate: ENV.fetch("REACTIVATE", "false")
    ).call
  end
end
