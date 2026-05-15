ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors) if respond_to?(:parallelize)
  end
end
