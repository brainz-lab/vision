FactoryBot.define do
  factory :task_step do
    association :ai_task
    position    { 0 }
    action      { "click" }
    selector    { "button.submit" }
    success     { true }
    executed_at { Time.current }

    trait :navigate do
      action   { "navigate" }
      selector { nil }
      value    { "https://example.com" }
    end

    trait :type do
      action   { "type" }
      selector { "input#email" }
      value    { "user@example.com" }
    end

    trait :fill do
      action   { "fill" }
      selector { "#password" }
      value    { "secret" }
    end

    trait :screenshot do
      action   { "screenshot" }
      selector { nil }
    end

    trait :done do
      action   { "done" }
      selector { nil }
    end

    trait :failed do
      success       { false }
      error_message { "Element not found: button.submit" }
    end

    trait :with_tokens do
      input_tokens  { 200 }
      output_tokens { 50 }
    end
  end
end
