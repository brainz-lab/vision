# frozen_string_literal: true

# Set Playwright browsers path for persistent storage
# This must be set before Playwright gem is loaded
ENV["PLAYWRIGHT_BROWSERS_PATH"] ||= Rails.root.join(".playwright").to_s
