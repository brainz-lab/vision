FactoryBot.define do
  factory :browser_session do
    association :project
    provider_session_id { "sess_#{SecureRandom.hex(16)}" }
    browser_provider    { "local" }
    status              { "active" }
    viewport            { { "width" => 1280, "height" => 720 } }
    metadata            { {} }
    expires_at          { 30.minutes.from_now }

    trait :initializing do
      status { "initializing" }
    end

    trait :idle do
      status { "idle" }
    end

    trait :error do
      status   { "error" }
      metadata { { "error" => "Connection refused" } }
    end

    trait :closed do
      status    { "closed" }
      closed_at { Time.current }
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :cloud do
      browser_provider    { "hyperbrowser" }
      provider_session_id { "hb_#{SecureRandom.hex(16)}" }
    end

    trait :with_url do
      current_url   { "https://example.com/dashboard" }
      current_title { "Dashboard" }
    end
  end
end
