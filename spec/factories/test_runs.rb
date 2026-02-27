FactoryBot.define do
  factory :test_run do
    association :project
    status               { "pending" }
    branch               { "main" }
    environment          { "staging" }
    triggered_by         { "api" }
    base_branch          { "main" }
    total_pages          { 0 }
    passed_count         { 0 }
    failed_count         { 0 }
    pending_count        { 0 }
    error_count          { 0 }
    notification_channels { [] }

    trait :running do
      status     { "running" }
      started_at { 1.minute.ago }
    end

    trait :passed do
      status       { "passed" }
      started_at   { 5.minutes.ago }
      completed_at { Time.current }
      total_pages  { 3 }
      passed_count { 3 }
    end

    trait :failed do
      status       { "failed" }
      started_at   { 5.minutes.ago }
      completed_at { Time.current }
      total_pages  { 3 }
      passed_count { 2 }
      failed_count { 1 }
    end

    trait :with_pr do
      pr_number  { 42 }
      pr_url     { "https://github.com/org/repo/pull/42" }
      base_branch { "main" }
    end
  end
end
