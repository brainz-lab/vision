# frozen_string_literal: true

module Ai
  # Injects credentials into browser automation flows
  # Handles login forms, API key inputs, and cookie injection
  #
  # Usage:
  #   injector = CredentialInjector.new(browser: browser, session_id: session_id, project: project)
  #   injector.login(credential)  # Performs full login flow
  #   injector.fill_credentials(credential)  # Just fills the form
  #
  class CredentialInjector
    class InjectionError < StandardError; end

    attr_reader :browser, :session_id, :project

    # Common login field selectors for fallback
    # Note: ASP.NET sites use ctl00$ prefixes, order matters - specific first
    USERNAME_SELECTORS = [
      'input#fldEmail',
      'input[id*="username"]',    # Matches ASP.NET IDs like ctl00_mainContent_username
      'input[name*="username"]',  # Matches ASP.NET names like ctl00$mainContent$username
      'input#username',
      'input[name="username"]',
      'input[name="email"]',
      'input[type="email"]',
      'input#email',
      'input[name="user"]',
      'input[name="login"]'
    ].freeze

    PASSWORD_SELECTORS = [
      'input#fldPassword',
      'input[id*="password"]',    # Matches ASP.NET IDs like ctl00_mainContent_password
      'input[name*="password"]',  # Matches ASP.NET names like ctl00$mainContent$password
      'input[type="password"]',
      'input[name="password"]',
      'input[name="pass"]',
      'input#password'
    ].freeze

    SUBMIT_SELECTORS = [
      'button.btn-primary',
      'button[type="submit"]',
      'input[type="submit"]',
      'button:has-text("Sign in")',
      'button:has-text("Log in")',
      'button:has-text("Login")',
      'button:has-text("Submit")'
    ].freeze

    def initialize(browser:, session_id:, project:)
      @browser = browser
      @session_id = session_id
      @project = project
    end

    # Common consent dialog selectors to dismiss before login
    CONSENT_SELECTORS = [
      '#accept-btn',           # Brickset/Quantcast style
      'button#agree-btn',
      'button:has-text("AGREE")',
      'button:has-text("Accept")',
      'button:has-text("Accept all")',
      'button:has-text("Accept All")',
      'button:has-text("I agree")',
      '.cmp-agree-button',
      '[data-testid="accept-cookies"]',
      '.cookie-accept',
      '#onetrust-accept-btn-handler',
      '.accept-cookies-button'
    ].freeze

    # Perform a full login flow using stored credentials
    # @param credential [Credential] The credential to use
    # @param options [Hash] Additional options
    # @return [Hash] Result of login attempt
    def login(credential, options = {})
      creds = credential.fetch
      selectors = credential.login_selectors

      Rails.logger.info "[CredentialInjector] Starting login for #{credential.name}"

      # Navigate to login page if specified
      if selectors[:login_url].present? && options[:navigate] != false
        Rails.logger.info "[CredentialInjector] Navigating to #{selectors[:login_url]}"
        @browser.navigate(@session_id, selectors[:login_url])
        wait_for_page_load
      end

      # Dismiss any consent dialogs first
      dismiss_consent_dialogs

      # Try configured selectors first, then fallback to common ones
      username_filled = smart_fill_field(:username, selectors[:username_field], creds[:username])
      password_filled = smart_fill_field(:password, selectors[:password_field], creds[:password])

      if !username_filled || !password_filled
        Rails.logger.warn "[CredentialInjector] Failed to fill some fields - username: #{username_filled}, password: #{password_filled}"
      end

      # Wait briefly for form validation
      sleep(0.5)

      # Submit form
      if options[:submit] != false
        smart_submit_form(selectors[:submit_button])
        wait_for_navigation
      end

      # Verify login success
      verify_login(credential, options)
    rescue VaultClient::VaultError => e
      Rails.logger.error "[CredentialInjector] Vault error: #{e.message}"
      { success: false, error: "Failed to fetch credentials: #{e.message}" }
    rescue => e
      Rails.logger.error "[CredentialInjector] Login failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
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

    # Dismiss common consent/cookie dialogs that may block login forms
    def dismiss_consent_dialogs
      Rails.logger.info "[CredentialInjector] Checking for consent dialogs..."

      CONSENT_SELECTORS.each do |selector|
        begin
          if element_exists?(selector)
            Rails.logger.info "[CredentialInjector] Found consent button: #{selector}"
            result = @browser.perform_action(
              @session_id,
              action: :click,
              selector: selector
            )

            if result[:success] != false
              Rails.logger.info "[CredentialInjector] Dismissed consent dialog with: #{selector}"
              sleep(1) # Wait for dialog to close
              return true
            end
          end
        rescue => e
          Rails.logger.debug "[CredentialInjector] Consent selector #{selector} failed: #{e.message}"
        end
      end

      Rails.logger.info "[CredentialInjector] No consent dialog found or dismissed"
      false
    end

    # Smart fill that tries multiple selectors
    def smart_fill_field(field_type, primary_selector, value)
      return false unless value.present?

      # Build list of selectors to try
      selectors_to_try = [primary_selector].compact
      selectors_to_try += case field_type
      when :username then USERNAME_SELECTORS
      when :password then PASSWORD_SELECTORS
      else []
      end

      selectors_to_try.uniq.each do |selector|
        next if selector.blank?

        begin
          # Try to fill the element directly - Playwright will tell us if it doesn't exist
          Rails.logger.debug "[CredentialInjector] Trying #{field_type} selector: #{selector}"
          result = @browser.perform_action(
            @session_id,
            action: :fill,
            selector: selector,
            value: value
          )

          if result[:success] != false
            Rails.logger.info "[CredentialInjector] Successfully filled #{field_type} using selector: #{selector}"
            return true
          else
            Rails.logger.debug "[CredentialInjector] Selector #{selector} returned: #{result.inspect}"
          end
        rescue => e
          Rails.logger.debug "[CredentialInjector] Selector #{selector} failed: #{e.message}"
        end
      end

      Rails.logger.warn "[CredentialInjector] Could not fill #{field_type} field with any selector"
      false
    end

    # Smart submit that tries multiple selectors
    def smart_submit_form(primary_selector)
      selectors_to_try = [primary_selector].compact + SUBMIT_SELECTORS

      selectors_to_try.uniq.each do |selector|
        next if selector.blank?

        begin
          if element_exists?(selector)
            result = @browser.perform_action(
              @session_id,
              action: :click,
              selector: selector
            )

            if result[:success] != false
              Rails.logger.info "[CredentialInjector] Successfully clicked submit using selector: #{selector}"
              return true
            end
          end
        rescue => e
          Rails.logger.debug "[CredentialInjector] Submit selector #{selector} failed: #{e.message}"
        end
      end

      # Last resort: press Enter
      Rails.logger.info "[CredentialInjector] Trying Enter key as submit fallback"
      @browser.perform_action(@session_id, action: :press, value: "Enter")
      true
    rescue => e
      Rails.logger.warn "[CredentialInjector] Submit failed: #{e.message}"
      false
    end

    # Check if an element exists on the page
    def element_exists?(selector)
      result = @browser.evaluate(
        @session_id,
        "(function() { try { return document.querySelector('#{selector.gsub("'", "\\\\'")}') !== null; } catch(e) { return false; } })()"
      )
      result == true
    rescue => e
      Rails.logger.debug "[CredentialInjector] element_exists? check failed for #{selector}: #{e.message}"
      # Return true to let the fill attempt happen (Playwright will report if it fails)
      true
    end

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
      sleep(2)
    end

    def wait_for_navigation
      Rails.logger.info "[CredentialInjector] Waiting 5 seconds for navigation..."
      sleep(5)  # Give more time for login redirects
      Rails.logger.info "[CredentialInjector] Wait complete"
    end

    def verify_login(credential, options)
      # Check for common success indicators
      current_url = @browser.current_url(@session_id)
      page_html = @browser.page_content(@session_id, format: :html)

      Rails.logger.info "[CredentialInjector] Post-login URL: #{current_url}"

      # Check if we're still on login page (indicates failure)
      login_url = credential.login_selectors[:login_url]
      still_on_login = login_url.present? && current_url.include?(URI.parse(login_url).path)

      # Check for specific error messages (be more restrictive to avoid false positives)
      error_patterns = [
        /invalid\s+(password|email|credentials)/i,
        /incorrect\s+(password|email|login)/i,
        /login\s+failed/i,
        /authentication\s+failed/i,
        /wrong\s+(password|email)/i,
        /error.*password/i,
        /password.*error/i
      ]
      has_error = error_patterns.any? { |pattern| page_html.match?(pattern) }

      # Check for success indicators (common logged-in elements)
      success_patterns = credential.metadata&.dig("success_patterns") || []
      has_success = success_patterns.any? { |pattern| page_html.match?(Regexp.new(pattern, Regexp::IGNORECASE)) }

      # Also check for common logged-in indicators
      has_logout = page_html.include?("signout") || page_html.include?("logout") || page_html.include?("Sign out")
      has_username = page_html.include?("legocolombia") || page_html.include?("My account")

      Rails.logger.info "[CredentialInjector] Login verification: still_on_login=#{still_on_login}, has_error=#{has_error}, has_logout=#{has_logout}, has_username=#{has_username}"

      if has_success || has_logout || has_username || (!still_on_login && !has_error)
        Rails.logger.info "[CredentialInjector] Login SUCCESSFUL for #{credential.name}"
        {
          success: true,
          url: current_url,
          message: "Login successful"
        }
      else
        Rails.logger.warn "[CredentialInjector] Login may have FAILED for #{credential.name}"
        {
          success: false,
          url: current_url,
          error: "Login may have failed - still on login page or error detected"
        }
      end
    end
  end
end
