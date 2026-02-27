FactoryBot.define do
  factory :test_case do
    association :project
    sequence(:name) { |n| "Test Case #{n}" }
    enabled  { true }
    position { 0 }
    steps do
      [
        { "action" => "navigate", "value" => "https://example.com" },
        { "action" => "screenshot" }
      ]
    end

    trait :disabled do
      enabled { false }
    end

    trait :with_login do
      steps do
        [
          { "action" => "navigate",   "value" => "https://example.com/login" },
          { "action" => "fill",       "selector" => "#email",    "value" => "user@example.com" },
          { "action" => "fill",       "selector" => "#password", "value" => "secret" },
          { "action" => "click",      "selector" => "button[type=submit]" },
          { "action" => "screenshot" }
        ]
      end
    end
  end
end
