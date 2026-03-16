FactoryBot.define do
  factory :project do
    platform_project_id { "platform_#{SecureRandom.hex(8)}" }
    name                 { "Test Project" }
    base_url             { "https://example.com" }
    environment          { "test" }
    settings do
      {
        "api_key"    => "vis_api_#{SecureRandom.hex(16)}",
        "ingest_key" => "vis_ingest_#{SecureRandom.hex(16)}"
      }
    end

    # Suppress the after_create callback that creates default browser configs,
    # so factories stay lean and tests control their own setup.
    after(:build) do |project|
      project.define_singleton_method(:create_default_browser_configs) { }
    end

    trait :with_browser_configs do
      after(:create) do |project|
        project.browser_configs.create!(
          browser: "chromium", name: "Chrome Desktop", width: 1280, height: 720, enabled: true
        )
        project.browser_configs.create!(
          browser: "chromium", name: "Chrome Mobile", width: 375, height: 812,
          is_mobile: true, has_touch: true, enabled: true
        )
      end
    end

    trait :archived do
      archived_at { 1.week.ago }
    end

    trait :with_ai do
      settings do
        {
          "api_key"    => "vis_api_#{SecureRandom.hex(16)}",
          "ingest_key" => "vis_ingest_#{SecureRandom.hex(16)}",
          "ai"         => {
            "enabled"                  => true,
            "default_model"            => "claude-sonnet-4",
            "default_browser_provider" => "local"
          }
        }
      end
    end
  end
end
