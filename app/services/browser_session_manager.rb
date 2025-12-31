# frozen_string_literal: true

# Manages browser sessions with provider fallback support
class BrowserSessionManager
  FALLBACK_ORDER = %w[hyperbrowser browserbase stagehand local].freeze

  attr_reader :project

  def initialize(project)
    @project = project
  end

  # Create a new browser session with fallback support
  # @param options [Hash] Session options
  # @return [BrowserSession] Created session
  def create_session(**options)
    preferred = options.delete(:provider) || project.default_browser_provider || "local"
    providers_to_try = build_fallback_list(preferred)

    last_error = nil

    providers_to_try.each do |provider_name|
      begin
        Rails.logger.info "Attempting to create session with #{provider_name}"

        provider = BrowserProviders::Factory.for_project(project, provider_override: provider_name)
        result = provider.create_session(**options)

        # Create session record
        session = project.browser_sessions.create!(
          provider_session_id: result[:session_id],
          browser_provider: provider_name,
          status: "active",
          start_url: options[:start_url],
          viewport: options[:viewport] || { width: 1280, height: 720 },
          metadata: result.except(:session_id, :provider),
          expires_at: 30.minutes.from_now
        )

        Rails.logger.info "Session created: #{session.id} with #{provider_name}"
        return session
      rescue => e
        Rails.logger.warn "Provider #{provider_name} failed: #{e.message}"
        last_error = e
        # Continue to next provider
      end
    end

    raise last_error || StandardError.new("All browser providers failed")
  end

  # Get the provider instance for a session
  # @param session [BrowserSession] Session record
  # @return [BrowserProviders::Base] Provider instance
  def provider_for(session)
    BrowserProviders::Factory.for_project(
      project,
      provider_override: session.browser_provider
    )
  end

  # Close a session
  # @param session [BrowserSession] Session to close
  def close_session(session)
    return if session.closed?

    begin
      provider = provider_for(session)
      provider.close_session(session.provider_session_id)
    rescue => e
      Rails.logger.warn "Failed to close session with provider: #{e.message}"
    ensure
      session.close!
    end
  end

  # Get or create a session for the project
  # Reuses existing active session if available
  # @param options [Hash] Session options
  # @return [BrowserSession] Session
  def get_or_create_session(**options)
    # Look for existing active session with matching provider
    preferred = options[:provider] || project.default_browser_provider || "local"

    existing = project.browser_sessions
                      .active
                      .where(browser_provider: preferred)
                      .where("expires_at > ?", Time.current)
                      .order(created_at: :desc)
                      .first

    if existing && session_alive?(existing)
      existing.extend_expiry!
      return existing
    end

    # Close stale session if exists
    existing&.close! if existing

    # Create new session
    create_session(**options)
  end

  # Check if a session is still alive
  # @param session [BrowserSession] Session to check
  # @return [Boolean]
  def session_alive?(session)
    return false if session.closed?
    return false if session.expired?

    provider = provider_for(session)
    provider.session_alive?(session.provider_session_id)
  rescue
    false
  end

  # Clean up expired sessions
  def cleanup_expired_sessions
    project.browser_sessions.expired.active.find_each do |session|
      close_session(session)
    end
  end

  # Get active sessions count
  def active_sessions_count
    project.browser_sessions.active.count
  end

  private

  def build_fallback_list(preferred)
    return [ preferred ] unless project.fallback_providers_enabled?

    list = [ preferred ]

    FALLBACK_ORDER.each do |provider|
      next if provider == preferred
      next unless provider_available?(provider)

      list << provider
    end

    list
  end

  def provider_available?(provider_name)
    return true if provider_name == "local"

    project.provider_configured?(provider_name)
  end
end
