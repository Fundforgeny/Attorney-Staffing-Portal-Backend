require "test_helper"
require "base64"

class GoogleSecretManagerSecretTest < ActiveSupport::TestCase
  setup do
    @original_project = ENV[GoogleSecretManagerSecret::PROJECT_ENV]
    @original_fallback_project = ENV[GoogleSecretManagerSecret::PROJECT_FALLBACK_ENV]
    @original_secret_project = ENV["GHL_AGENCY_API_KEY#{GoogleSecretManagerSecret::SECRET_PROJECT_ENV_SUFFIX}"]
    @original_oauth_token = ENV["GOOGLE_OAUTH_ACCESS_TOKEN"]
  end

  teardown do
    restore_env(GoogleSecretManagerSecret::PROJECT_ENV, @original_project)
    restore_env(GoogleSecretManagerSecret::PROJECT_FALLBACK_ENV, @original_fallback_project)
    restore_env("GHL_AGENCY_API_KEY#{GoogleSecretManagerSecret::SECRET_PROJECT_ENV_SUFFIX}", @original_secret_project)
    restore_env("GOOGLE_OAUTH_ACCESS_TOKEN", @original_oauth_token)
  end

  test "returns nil when no project is configured" do
    ENV.delete(GoogleSecretManagerSecret::PROJECT_ENV)
    ENV.delete(GoogleSecretManagerSecret::PROJECT_FALLBACK_ENV)
    ENV.delete("GHL_AGENCY_API_KEY#{GoogleSecretManagerSecret::SECRET_PROJECT_ENV_SUFFIX}")

    assert_nil GoogleSecretManagerSecret.fetch("GHL_AGENCY_API_KEY")
  end

  test "uses secret-specific project before global project" do
    ENV[GoogleSecretManagerSecret::PROJECT_ENV] = "global-project"
    ENV["GHL_AGENCY_API_KEY#{GoogleSecretManagerSecret::SECRET_PROJECT_ENV_SUFFIX}"] = "secret-project"

    assert_equal "secret-project", GoogleSecretManagerSecret.project_for("GHL_AGENCY_API_KEY")
  end

  test "fetch passes resolved project and token to the secret reader" do
    ENV[GoogleSecretManagerSecret::PROJECT_ENV] = "titans-app-test"

    GoogleSecretManagerSecret.stubs(:access_token).returns("test-oauth-token")
    GoogleSecretManagerSecret.expects(:read_secret)
                            .with("GHL_AGENCY_API_KEY", "titans-app-test", "test-oauth-token")
                            .returns("test-agency-key")

    assert_equal "test-agency-key", GoogleSecretManagerSecret.fetch("GHL_AGENCY_API_KEY")
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
