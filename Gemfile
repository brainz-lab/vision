source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.1"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Redis for Action Cable in development
gem "redis", "~> 5.0"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# ============================================
# Vision-specific dependencies
# ============================================

# Playwright for browser automation
gem "playwright-ruby-client"

# Image processing for screenshots
gem "image_processing", "~> 1.2"
gem "mini_magick"
gem "ruby-vips"

# AWS SDK for S3-compatible storage (MinIO in development)
gem "aws-sdk-s3", require: false

# Connection pooling for browser instances
gem "connection_pool"

# HTTP client with retries for external API calls
gem "faraday", "~> 2.14"
gem "faraday-retry"

gem "brainzlab", "~> 0.1.12"
if ENV["BUNDLE_DEPLOYMENT"] == "1"
  gem "brainzlab-ui", "~> 0.1.0"
elsif File.exist?("/brainzlab-ui")
  gem "brainzlab-ui", path: "/brainzlab-ui"
elsif File.exist?(File.expand_path("../brainzlab-ui", __dir__))
  gem "brainzlab-ui", path: "../brainzlab-ui"
else
  gem "brainzlab-ui", "~> 0.1.0"
end

gem "phlex-rails", "~> 2.0"

group :development, :test do
  # Lock minitest to compatible version with Rails 8
  gem "minitest", "~> 5.25"
  gem "simplecov", require: false
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "lefthook", require: false
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end
