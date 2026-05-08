# frozen_string_literal: true

# Vault recovery reporting tasks.
#
# These tasks are read-only. They do not charge cards, redact cards, archive cards,
# restore cards, or modify payment/payment_method records.
#
# Manual run from Render shell:
#   bundle exec rails vault:recovery_report
#
namespace :vault do
  desc "Print a read-only vault recovery report for payment methods and payments needing cards"
  task recovery_report: :environment do
    VaultRecoveryReporter.new.print_report
  end
end
