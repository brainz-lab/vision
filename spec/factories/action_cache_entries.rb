FactoryBot.define do
  factory :action_cache_entry do
    association :project
    url_pattern    { "example.com/dashboard" }
    action_type    { "click" }
    action_data    { { "selector" => "button.submit", "text" => "Submit" } }
    success_count  { 5 }
    failure_count  { 0 }
    expires_at     { 24.hours.from_now }
    last_used_at   { Time.current }

    trait :navigate do
      action_type { "navigate" }
      action_data { { "url" => "https://example.com/dashboard" } }
    end

    trait :fill do
      action_type { "fill" }
      action_data { { "selector" => "#email", "value" => "user@example.com" } }
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :unreliable do
      success_count { 1 }
      failure_count { 5 }
    end

    trait :with_duration do
      avg_duration_ms { 120.0 }
    end
  end
end
