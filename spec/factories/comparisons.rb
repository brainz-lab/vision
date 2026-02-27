FactoryBot.define do
  factory :comparison do
    association :baseline
    association :snapshot
    status           { "passed" }
    diff_percentage  { 0.0 }
    diff_pixels      { 0 }
    threshold_used   { 0.01 }
    within_threshold { true }
    review_status    { nil }

    trait :failed do
      status           { "failed" }
      diff_percentage  { 5.2 }
      diff_pixels      { 1024 }
      within_threshold { false }
      review_status    { "pending" }
    end

    trait :approved do
      status        { "failed" }
      diff_percentage { 5.2 }
      review_status { "approved" }
      reviewed_at   { Time.current }
      reviewed_by   { "reviewer@example.com" }
    end

    trait :rejected do
      status        { "failed" }
      review_status { "rejected" }
      reviewed_at   { Time.current }
      reviewed_by   { "reviewer@example.com" }
      review_notes  { "Visual regression detected" }
    end

    trait :error do
      status { "error" }
    end

    trait :with_test_run do
      association :test_run
    end
  end
end
