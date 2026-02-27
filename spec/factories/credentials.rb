FactoryBot.define do
  factory :credential do
    association :project
    sequence(:name) { |n| "credential-#{n}" }
    credential_type  { "login" }
    service_url      { "https://example.com/*" }
    active           { true }
    vault_environment { "test" }
    metadata         { {} }
    use_count        { 0 }
    # vault_path is auto-set by before_validation callback from project + name

    trait :api_key do
      credential_type { "api_key" }
      service_url     { "https://api.example.com/*" }
    end

    trait :inactive do
      active { false }
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :with_selectors do
      metadata do
        {
          "username_field" => "#email",
          "password_field" => "#password",
          "submit_button"  => "button[type=submit]",
          "login_url"      => "https://example.com/login"
        }
      end
    end
  end
end
