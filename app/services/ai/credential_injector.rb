# frozen_string_literal: true

module Ai
  # Injects credentials into browser automation flows
  # Handles login forms, API key inputs, and cookie injection
  #
  # Usage:
  #   injector = CredentialInjector.new(browser: browser, session_id: session_id)
  #   injector.login(credential)  # Performs full login flow
  #   injector.fill_credentials(credential)  # Just fills the form
  #
  class CredentialInjector
    class InjectionError < StandardError; end

    attr_reader :browser, :session_id, :project

    def initialize(browser:, session_id:, project:)
      @browser = browser
      @session_id = session_id
      @project = project
    end

    # Perform a full login flow using stored credentials
    # @param credential [Credential] The credential to use
    # @param options [Hash] Additional options
    # @return [Hash] Result of login attempt
    def login(credential, options = {})
      creds = credential.fetch
      selectors = credential.login_selectors

      # Navigate to login page if specified
      if selectors[:login_url].present? && options[:navigate] != false
        @browser.navigate(@session_id, selectors[:login_url])
        wait_for_page_load
      end

      # Fill username
      fill_field(selectors[:username_field], creds[:username])

      # Fill password
      fill_field(selectors[:password_field], creds[:password])

      # Wait briefly for form validation
      sleep(0.3)

      # Submit form
      if options[:submit] != false
        submit_form(selectors[:submit_button])
        wait_for_navigation
      end

      # Verify login success
      verify_login(credential, options)
    rescue VaultClient::VaultError => e
      { success: false, error: "Failed to fetch credentials: #{e.message}" }
    rescue => e
      { success: false, error: "Login failed: #{e.message}" }
    end

    # Fill credential fields without submitting
    # @param credential [Credential] The credential to use
    # @return [Hash] Result
    def fill_credentials(credential)
      creds = credential.fetch
      selectors = credential.login_selectors

      username_filled = fill_field(selectors[:username_field], creds[:username])
      password_filled = fill_field(selectors[:password_field], creds[:password])

      {
        success: username_filled && password_filled,
        username_filled: username_filled,
        password_filled: password_filled
      }
    rescue VaultClient::VaultError => e
      { success: false, error: "Failed to fetch credentials: #{e.message}" }
    end

    # Fill a specific field with a value from Vault
    # @param field_name [String] Name of the credential field
    # @param selector [String] CSS selector for the input
    # @param credential [Credential] The credential to use
    def fill_from_vault(field_name, selector, credential)
      creds = credential.fetch
      value = creds[field_name.to_sym]

      raise InjectionError, "Field #{field_name} not found in credential" unless value

      fill_field(selector, value)
    end

    # Inject cookies from credential (for session-based auth)
    # @param credential [Credential] Cookie credential
    def inject_cookies(credential)
      creds = credential.fetch
      cookies = creds[:cookies] || []

      cookies.each do |cookie|
        @browser.set_cookie(@session_id, cookie)
      end

      { success: true, cookies_injected: cookies.length }
    rescue => e
      { success: false, error: "Cookie injection failed: #{e.message}" }
    end

    # Inject bearer token into page (for SPA auth)
    # @param credential [Credential] Bearer token credential
    def inject_bearer_token(credential)
      creds = credential.fetch
      token = creds[:token] || creds[:bearer_token] || creds[:access_token]

      raise InjectionError, "No token found in credential" unless token

      # Inject into localStorage (common for SPAs)
      storage_key = credential.metadata["storage_key"] || "access_token"

      @browser.execute_script(@session_id, <<~JS)
        localStorage.setItem('#{storage_key}', '#{token}');
      JS

      { success: true, storage_key: storage_key }
    rescue => e
      { success: false, error: "Token injection failed: #{e.message}" }
    end

    # Auto-detect and inject credentials based on current page
    # @param credential [Credential] The credential to use
    # @return [Hash] Result
    def auto_inject(credential)
      case credential.credential_type
      when "login"
        fill_credentials(credential)
      when "cookie"
        inject_cookies(credential)
      when "bearer"
        inject_bearer_token(credential)
      when "api_key"
        # API keys typically need custom handling
        { success: false, error: "API key injection requires specific selector" }
      else
        { success: false, error: "Unknown credential type: #{credential.credential_type}" }
      end
    end

    private

    def fill_field(selector, value)
      return false unless value.present?

      result = @browser.perform_action(
        @session_id,
        action: :fill,
        selector: selector,
        value: value
      )

      result[:success] != false
    rescue => e
      Rails.logger.warn "Failed to fill field #{selector}: #{e.message}"
      false
    end

    def submit_form(selector)
      @browser.perform_action(
        @session_id,
        action: :click,
        selector: selector
      )
    rescue => e
      # Try pressing Enter as fallback
      @browser.perform_action(@session_id, action: :press, value: "Enter")
    end

    def wait_for_page_load
      sleep(1)
    end

    def wait_for_navigation
      sleep(2)
    end

    def verify_login(credential, options)
      # Check for common success indicators
      current_url = @browser.current_url(@session_id)
      page_html = @browser.page_content(@session_id, format: :html)

      # Check if we're still on login page (indicates failure)
      login_url = credential.login_selectors[:login_url]
      still_on_login = login_url.present? && current_url.include?(URI.parse(login_url).path)

      # Check for error messages
      has_error = page_html.match?(/error|invalid|incorrect|failed/i) &&
                  page_html.match?(/password|login|credential|authentication/i)

      # Check for success indicators
      success_patterns = credential.metadata["success_patterns"] || []
      has_success = success_patterns.any? { |pattern| page_html.match?(Regexp.new(pattern, Regexp::IGNORECASE)) }

      if has_success || (!still_on_login && !has_error)
        {
          success: true,
          url: current_url,
          message: "Login successful"
        }
      else
        {
          success: false,
          url: current_url,
          error: "Login may have failed - still on login page or error detected"
        }
      end
    end
  end
end
