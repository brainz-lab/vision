# frozen_string_literal: true

module BrowserProviders
  # Abstract base class for browser providers
  # All providers must implement the core interface methods
  class Base
    attr_reader :config

    def initialize(config = {})
      @config = config
    end

    # Create a new browser session
    # @param options [Hash] Session options (viewport, headless, etc.)
    # @return [Hash] { session_id:, provider:, ... }
    def create_session(**options)
      raise NotImplementedError, "#{self.class} must implement #create_session"
    end

    # Close a browser session
    # @param session_id [String] Session identifier
    def close_session(session_id)
      raise NotImplementedError, "#{self.class} must implement #close_session"
    end

    # Navigate to a URL
    # @param session_id [String] Session identifier
    # @param url [String] URL to navigate to
    # @return [Hash] { url:, title: }
    def navigate(session_id, url)
      raise NotImplementedError, "#{self.class} must implement #navigate"
    end

    # Perform a browser action
    # @param session_id [String] Session identifier
    # @param action [String] Action type (click, type, fill, etc.)
    # @param selector [String, nil] CSS/XPath selector
    # @param value [String, nil] Value for the action
    # @param options [Hash] Additional options
    # @return [Hash] { success:, url:, error: }
    def perform_action(session_id, action:, selector: nil, value: nil, **options)
      raise NotImplementedError, "#{self.class} must implement #perform_action"
    end

    # Take a screenshot
    # @param session_id [String] Session identifier
    # @param options [Hash] Screenshot options (full_page, type, etc.)
    # @return [Hash] { data: [binary], content_type: }
    def screenshot(session_id, **options)
      raise NotImplementedError, "#{self.class} must implement #screenshot"
    end

    # Get page content
    # @param session_id [String] Session identifier
    # @param format [Symbol] :html, :text, or :accessibility
    # @return [String] Page content
    def page_content(session_id, format: :html)
      raise NotImplementedError, "#{self.class} must implement #page_content"
    end

    # Get current URL
    # @param session_id [String] Session identifier
    # @return [String] Current URL
    def current_url(session_id)
      raise NotImplementedError, "#{self.class} must implement #current_url"
    end

    # Get current page title
    # @param session_id [String] Session identifier
    # @return [String] Page title
    def current_title(session_id)
      raise NotImplementedError, "#{self.class} must implement #current_title"
    end

    # Execute JavaScript
    # @param session_id [String] Session identifier
    # @param script [String] JavaScript code
    # @return [Object] Script result
    def evaluate(session_id, script)
      raise NotImplementedError, "#{self.class} must implement #evaluate"
    end

    # Wait for a selector to appear
    # @param session_id [String] Session identifier
    # @param selector [String] CSS/XPath selector
    # @param timeout [Integer] Timeout in milliseconds
    def wait_for_selector(session_id, selector, timeout: 30_000)
      raise NotImplementedError, "#{self.class} must implement #wait_for_selector"
    end

    # Wait for navigation to complete
    # @param session_id [String] Session identifier
    # @param options [Hash] Wait options
    def wait_for_navigation(session_id, **options)
      raise NotImplementedError, "#{self.class} must implement #wait_for_navigation"
    end

    # Check if session is alive
    # @param session_id [String] Session identifier
    # @return [Boolean]
    def session_alive?(session_id)
      raise NotImplementedError, "#{self.class} must implement #session_alive?"
    end

    # Provider metadata
    def provider_name
      raise NotImplementedError, "#{self.class} must implement #provider_name"
    end

    def cloud?
      false
    end

    def local?
      !cloud?
    end

    def supports_cdp?
      false
    end

    protected

    def credentials
      @config[:credentials] || @config
    end

    def api_key
      credentials[:api_key]
    end

    def log_action(action, details = {})
      Rails.logger.debug "[#{provider_name}] #{action}: #{details.to_json}"
    end

    def log_error(action, error)
      Rails.logger.error "[#{provider_name}] #{action} error: #{error.message}"
    end
  end
end
