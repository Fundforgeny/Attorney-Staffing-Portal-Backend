source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "sprockets-rails"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.6"

# Use Active Record 7.1 features
gem 'activerecord', '~> 8.0.0'

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# =============================================================================
# Asset Handling (JS, CSS, etc.)
# =============================================================================
# Bundle and transpile JavaScript [https://github.com/rails/jsbundling-rails]
gem "jsbundling-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Bundle and process CSS [https://github.com/rails/cssbundling-rails]
gem "cssbundling-rails"
# Sass compiler for Rails
gem "sassc-rails"
# =============================================================================
# API and Data
# =============================================================================
# For JSON Responses
gem "blueprinter", "~> 1.1", ">= 1.1.2"

# Use Active Storage variants for image manipulation [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# Use Redis adapter to run Action Cable in production
gem "redis", ">= 4.0.1"

# Use stripe for payment processing 
gem 'stripe'

# Use square for payment processing
gem "square.rb"

# Evervault for data encryption and security
gem 'evervault'

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

gem "httparty", "~> 0.23.2"

# =============================================================================
# User Management and Authorization
# =============================================================================
# Flexible authentication solution
gem "devise"
# JWT support for Devise
gem "devise-jwt"
# Provides a simple way to configure CORS
gem "rack-cors"

# Role management for your models
gem "rolify"
# Authorization library based on a simple policy object
gem "pundit"

# Row-level Multi-Tenancy
gem "acts_as_tenant"

# For Admin Panels
gem "activeadmin"
gem "arctic_admin"
gem "activity_notification", "~> 2.3.3"

# =============================================================================
# Utilities and Background Jobs
# =============================================================================
# Background job processing
gem "sidekiq"

gem "sidekiq-failures"

# Collection of all sorts of useful information for every country in the ISO 3166 standard.
gem "countries", "~> 5.7"
# Provides a simple helper to get an HTML select list of countries using the ISO 3166-1 standard.
gem "country_select", "~> 8.0"
# Phone number validation and parsing
gem "phonelib"

# Pagination library
gem "kaminari"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

gem "aws-sdk-s3"

gem "active_storage_validations"
gem "liquid"
gem "font_awesome_icons_list"
gem "paper_trail", "~> 15.2"

# =============================================================================
# Development and Testing
# =============================================================================
group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", "~> 7.1.1", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Loads environment variables from a .env file
  gem "dotenv-rails"

  # Opens sent emails in the browser instead of sending them
  gem "letter_opener", "~> 1.10"

  # pry
  gem "pry"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  # Minitest test reporters for better test output
  gem "minitest-reporters"
  # Mocking and stubbing library for testing
  gem "mocha", require: false
end
