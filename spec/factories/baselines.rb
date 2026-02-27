FactoryBot.define do
  factory :baseline do
    association :page
    association :browser_config
    branch     { "main" }
    active     { true }
    width      { 1280 }
    height     { 720 }
    approved_at { Time.current }
    approved_by { "test@example.com" }

    trait :inactive do
      active { false }
    end

    trait :feature_branch do
      branch { "feature/test-branch" }
    end
  end
end
