# TODO Test and confirm if this config is what is needed

require "acts_as_tenant/sidekiq"

ActsAsTenant.configure do |config|
  config.require_tenant = false
end

# Manually switch tenant in console:
# ActsAsTenant.current_tenant = Location.find_by(name: "Some Location")
# or
# ActsAsTenant.with_tenant(Location.find_by(name: "Some Location")) do
#   User.create!(...) # will be auto-scoped
# end
