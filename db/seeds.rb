# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create a demo project for development
if Rails.env.development?
  project = Project.find_or_create_by!(platform_project_id: 'demo_vision_project') do |p|
    p.name = 'Demo Project'
    p.base_url = 'https://example.com'
    p.staging_url = 'https://staging.example.com'
    p.settings = {
      'default_viewport' => { 'width' => 1280, 'height' => 720 },
      'threshold' => 0.01,
      'wait_before_capture' => 500
    }
  end

  # Create default browser configs
  project.browser_configs.find_or_create_by!(browser: 'chromium', name: 'Chrome Desktop') do |bc|
    bc.width = 1280
    bc.height = 720
  end

  project.browser_configs.find_or_create_by!(browser: 'chromium', name: 'Chrome Mobile') do |bc|
    bc.width = 375
    bc.height = 812
    bc.is_mobile = true
    bc.has_touch = true
  end

  # Create sample pages
  project.pages.find_or_create_by!(slug: 'homepage') do |page|
    page.name = 'Homepage'
    page.path = '/'
  end

  project.pages.find_or_create_by!(slug: 'about') do |page|
    page.name = 'About Page'
    page.path = '/about'
  end

  puts "Seeded Vision development data"
end
