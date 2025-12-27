class Project < ApplicationRecord
  has_many :pages, dependent: :destroy
  has_many :browser_configs, dependent: :destroy
  has_many :test_runs, dependent: :destroy
  has_many :test_cases, dependent: :destroy
  has_many :baselines, through: :pages
  has_many :snapshots, through: :pages

  # AI Browser Automation associations
  has_many :ai_tasks, dependent: :destroy
  has_many :browser_sessions, dependent: :destroy
  has_many :action_cache_entries, dependent: :destroy

  # Vault integration for secure credential storage
  has_many :credentials, dependent: :destroy

  validates :platform_project_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :base_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }

  after_create :create_default_browser_configs

  def self.find_or_create_for_platform!(platform_project_id:, name: nil, environment: 'live')
    find_or_create_by!(platform_project_id: platform_project_id) do |p|
      p.name = name || "Project #{platform_project_id}"
      p.base_url = 'https://example.com'
      p.environment = environment
    end
  end

  def default_viewport
    settings['default_viewport'] || { 'width' => 1280, 'height' => 720 }
  end

  def threshold
    settings['threshold'] || 0.01
  end

  def wait_before_capture
    settings['wait_before_capture'] || 500
  end

  def hide_selectors
    settings['hide_selectors'] || []
  end

  def mask_selectors
    settings['mask_selectors'] || []
  end

  # Summary of recent test runs
  def recent_summary(since: 7.days.ago)
    runs = test_runs.where('created_at >= ?', since)
    {
      total_runs: runs.count,
      passed: runs.where(status: 'passed').count,
      failed: runs.where(status: 'failed').count,
      pass_rate: runs.count.positive? ? (runs.where(status: 'passed').count.to_f / runs.count * 100).round(1) : 0
    }
  end

  # ============================================
  # AI Configuration Accessors
  # ============================================

  # Get AI settings from project settings JSONB
  def ai_settings
    settings['ai'] || {}
  end

  # LLM Configuration
  def default_llm_model
    ai_settings['default_model'] || 'claude-sonnet-4'
  end

  def default_llm_model=(model)
    update_ai_setting('default_model', model)
  end

  # Browser Provider Configuration
  def default_browser_provider
    ai_settings['default_browser_provider'] || 'local'
  end

  def default_browser_provider=(provider)
    update_ai_setting('default_browser_provider', provider)
  end

  # Fallback settings
  def fallback_providers_enabled?
    ai_settings['fallback_providers_enabled'] != false
  end

  def max_task_timeout
    ai_settings['max_task_timeout'] || 600
  end

  # Check if a provider is configured
  def provider_configured?(provider_name)
    ai_settings.dig('providers', provider_name.to_s).present?
  end

  # Get LLM provider configuration
  # @param provider_type [Symbol] :anthropic, :openai, or :gemini
  # @return [Hash] Configuration with :api_key
  def llm_provider_config(provider_type)
    config = ai_settings.dig('providers', provider_type.to_s) || {}
    result = config.symbolize_keys

    # Decrypt API key if encrypted
    if result[:api_key_encrypted].present?
      result[:api_key] = decrypt_credential(result[:api_key_encrypted])
    end

    # Fall back to environment variable
    result[:api_key] ||= ENV["#{provider_type.to_s.upcase}_API_KEY"]

    result
  end

  # Get browser provider configuration
  # @param provider_name [String] Provider name (hyperbrowser, browserbase, etc.)
  # @return [Hash] Configuration with credentials
  def browser_provider_config(provider_name)
    config = ai_settings.dig('providers', provider_name.to_s) || {}
    result = config.symbolize_keys

    # Decrypt API key if encrypted
    if result[:api_key_encrypted].present?
      result[:api_key] = decrypt_credential(result[:api_key_encrypted])
    end

    # Fall back to environment variable
    result[:api_key] ||= ENV["#{provider_name.to_s.upcase}_API_KEY"]

    result
  end

  # Update provider credentials
  # @param provider_name [String] Provider name
  # @param credentials [Hash] Credentials to store (:api_key, :project_id, etc.)
  def update_provider_credentials(provider_name, credentials)
    providers = ai_settings['providers'] || {}

    provider_config = providers[provider_name.to_s] || {}

    # Encrypt API key
    if credentials[:api_key].present?
      provider_config['api_key_encrypted'] = encrypt_credential(credentials[:api_key])
    end

    # Store other credentials
    provider_config['project_id'] = credentials[:project_id] if credentials[:project_id].present?

    providers[provider_name.to_s] = provider_config
    update_ai_setting('providers', providers)
  end

  # Check if AI automation is enabled
  def ai_automation_enabled?
    ai_settings['enabled'] != false
  end

  # AI task configuration
  def ai_task_defaults
    {
      max_steps: ai_settings['max_steps'] || 25,
      timeout_seconds: ai_settings['timeout_seconds'] || 300,
      capture_screenshots: ai_settings.fetch('capture_screenshots', true),
      retry_count: ai_settings['retry_count'] || 3
    }
  end

  # ============================================
  # Vault Integration
  # ============================================

  # Get Vault access token for this project
  def vault_access_token
    # First check encrypted storage
    if settings.dig('vault', 'access_token_encrypted').present?
      decrypt_credential(settings.dig('vault', 'access_token_encrypted'))
    else
      # Fall back to environment variable
      ENV["VAULT_ACCESS_TOKEN"]
    end
  end

  # Set Vault access token (encrypted)
  def vault_access_token=(token)
    vault_settings = settings['vault'] || {}
    vault_settings['access_token_encrypted'] = encrypt_credential(token)
    update!(settings: settings.merge('vault' => vault_settings))
  end

  # Check if Vault integration is configured
  def vault_configured?
    vault_access_token.present?
  end

  # Find credential by name for this project
  def find_credential(name)
    credentials.active.find_by(name: name)
  end

  # Find credential matching a URL
  def credential_for_url(url)
    credentials.active.for_url(url).first
  end

  private

  def create_default_browser_configs
    browser_configs.create!([
      { browser: 'chromium', name: 'Chrome Desktop', width: 1280, height: 720 },
      { browser: 'chromium', name: 'Chrome Mobile', width: 375, height: 812, is_mobile: true, has_touch: true }
    ])
  end

  # Update a single AI setting
  def update_ai_setting(key, value)
    current_ai = settings['ai'] || {}
    current_ai[key] = value
    update!(settings: settings.merge('ai' => current_ai))
  end

  # Encrypt a credential for storage
  def encrypt_credential(value)
    return nil if value.blank?

    encryptor.encrypt_and_sign(value)
  end

  # Decrypt a stored credential
  def decrypt_credential(encrypted_value)
    return nil if encrypted_value.blank?

    encryptor.decrypt_and_verify(encrypted_value)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    Rails.logger.warn "Failed to decrypt credential for project #{id}"
    nil
  end

  # Get the message encryptor for credential encryption
  def encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(encryption_key)
  end

  # Derive an encryption key from Rails secret
  def encryption_key
    ActiveSupport::KeyGenerator.new(
      Rails.application.credentials.secret_key_base || Rails.application.secret_key_base
    ).generate_key('vision_credentials', 32)
  end
end
