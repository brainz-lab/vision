FactoryBot.define do
  factory :browser_config do
    association :project
    browser  { "chromium" }
    name     { "Chrome Desktop" }
    width    { 1280 }
    height   { 720 }
    enabled  { true }

    trait :firefox do
      browser { "firefox" }
      name    { "Firefox Desktop" }
    end

    trait :webkit do
      browser { "webkit" }
      name    { "Safari Desktop" }
    end

    trait :mobile do
      name      { "Chrome Mobile" }
      width     { 375 }
      height    { 812 }
      is_mobile { true }
      has_touch { true }
    end

    trait :disabled do
      enabled { false }
    end
  end
end
