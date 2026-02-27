FactoryBot.define do
  factory :snapshot do
    association :page
    association :browser_config
    status      { "pending" }
    branch      { "main" }
    environment { "staging" }
    metadata    { {} }

    trait :captured do
      status      { "captured" }
      captured_at { Time.current }
    end

    trait :comparing do
      status { "comparing" }
    end

    trait :compared do
      status { "compared" }
    end

    trait :error do
      status   { "error" }
      metadata { { "error" => "Connection timeout" } }
    end

    trait :with_test_run do
      association :test_run
    end
  end
end
