require "test_helper"

class TalentHubGhlConfigTest < ActiveSupport::TestCase
  setup do
    @original_api_key = ENV[TalentHubGhlConfig::API_KEY_ENV]
    @original_location_id = ENV[TalentHubGhlConfig::LOCATION_ID_ENV]
  end

  teardown do
    restore_env(TalentHubGhlConfig::API_KEY_ENV, @original_api_key)
    restore_env(TalentHubGhlConfig::LOCATION_ID_ENV, @original_location_id)
  end

  test "configured is false when either required env var is missing" do
    ENV.delete(TalentHubGhlConfig::API_KEY_ENV)
    ENV[TalentHubGhlConfig::LOCATION_ID_ENV] = "location_123"

    assert_not TalentHubGhlConfig.configured?
  end

  test "require config raises a safe message without secret values" do
    ENV.delete(TalentHubGhlConfig::API_KEY_ENV)
    ENV.delete(TalentHubGhlConfig::LOCATION_ID_ENV)

    error = assert_raises(TalentHubGhlConfig::MissingConfigError) do
      TalentHubGhlConfig.require_config!
    end

    assert_includes error.message, TalentHubGhlConfig::API_KEY_ENV
    assert_includes error.message, TalentHubGhlConfig::LOCATION_ID_ENV
    assert_not_includes error.message, "Bearer"
  end

  test "ghl service is initialized from configured env vars" do
    ENV[TalentHubGhlConfig::API_KEY_ENV] = "test_token"
    ENV[TalentHubGhlConfig::LOCATION_ID_ENV] = "location_123"

    service = TalentHubGhlConfig.ghl_service

    assert_instance_of GhlService, service
    assert TalentHubGhlConfig.configured?
  end

  private

  def restore_env(key, value)
    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end
  end
end
