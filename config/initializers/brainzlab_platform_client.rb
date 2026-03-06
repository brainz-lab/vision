# frozen_string_literal: true

return unless ENV["SERVICE_KEY"]

BrainzLab::PlatformClient.configure do |config|
  config.service_name = "vision"
  config.service_key  = ENV["SERVICE_KEY"]
  config.platform_url = ENV.fetch("BRAINZLAB_PLATFORM_URL", "http://localhost:3000")
end
