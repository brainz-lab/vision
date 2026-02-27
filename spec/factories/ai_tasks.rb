FactoryBot.define do
  factory :ai_task do
    association :project
    instruction      { "Click the login button and verify the dashboard loads" }
    status           { "pending" }
    model            { "claude-sonnet-4" }
    browser_provider { "local" }
    max_steps        { 25 }
    timeout_seconds  { 300 }
    triggered_by     { "api" }
    capture_screenshots { true }
    steps_executed   { 0 }
    viewport         { { "width" => 1280, "height" => 720 } }
    metadata         { {} }
    extracted_data   { {} }

    trait :running do
      status     { "running" }
      started_at { 1.minute.ago }
    end

    trait :completed do
      status       { "completed" }
      started_at   { 2.minutes.ago }
      completed_at { Time.current }
      steps_executed { 5 }
      result       { "Task completed successfully" }
    end

    trait :stopped do
      status        { "stopped" }
      completed_at  { Time.current }
      error_message { "Task stopped by user" }
    end

    trait :timed_out do
      status        { "timeout" }
      completed_at  { Time.current }
      error_message { "Task exceeded 300s time limit" }
    end

    trait :errored do
      status        { "error" }
      completed_at  { Time.current }
      error_message { "Browser connection refused" }
    end

    trait :mcp do
      triggered_by { "mcp" }
    end

    trait :with_tokens do
      total_input_tokens  { 1500 }
      total_output_tokens { 800 }
    end
  end
end
