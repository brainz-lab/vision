# Playwright configuration for Vision
# This initializer sets up the Playwright browser automation

Rails.application.config.to_prepare do
  # Configure Playwright paths
  ENV['PLAYWRIGHT_BROWSERS_PATH'] ||= Rails.root.join('.cache/ms-playwright').to_s
end
