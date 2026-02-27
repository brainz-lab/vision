module ApiHelpers
  # Vision API key auth (vis_api_* stored in settings JSONB)
  def auth_headers(project)
    { "Authorization" => "Bearer #{project.settings['api_key']}" }
  end

  # X-API-Key header variant
  def api_key_headers(project)
    { "X-API-Key" => project.settings["api_key"] }
  end

  # Master key for provision endpoint (VISION_MASTER_KEY)
  def master_key_headers(key = nil)
    key ||= ENV.fetch("VISION_MASTER_KEY", "test_master_key_vision")
    { "X-Master-Key" => key }
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
end
