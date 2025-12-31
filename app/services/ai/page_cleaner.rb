# frozen_string_literal: true

module Ai
  # Handles automatic cleanup of page obstacles like cookie banners, modals, and popups
  # Runs before AI task execution to ensure clean interaction
  class PageCleaner
    # Common cookie consent selectors
    COOKIE_CONSENT_SELECTORS = [
      # Accept buttons
      'button:has-text("Accept")',
      'button:has-text("Accept all")',
      'button:has-text("Accept All")',
      'button:has-text("I Accept")',
      'button:has-text("Agree")',
      'button:has-text("OK")',
      'button:has-text("Got it")',
      'button:has-text("Allow")',
      'button:has-text("Allow all")',
      'button:has-text("Allow All")',
      'button:has-text("Consent")',
      "button#onetrust-accept-btn-handler",
      "button.accept-cookies",
      "button.cookie-accept",
      'button[data-testid="accept-cookies"]',
      "button.js-accept-cookies",
      # Close buttons on consent dialogs
      '[aria-label="Close cookie banner"]',
      ".cookie-banner button.close",
      ".cookie-notice button.close",
      ".gdpr-banner button.close",
      # Specific frameworks
      "#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll",
      "#didomi-notice-agree-button",
      ".fc-button.fc-cta-consent",
      '.qc-cmp2-summary-buttons button[mode="primary"]'
    ].freeze

    # Common popup/modal close selectors
    POPUP_CLOSE_SELECTORS = [
      'button[aria-label="Close"]',
      'button[aria-label="Dismiss"]',
      "button.modal-close",
      "button.popup-close",
      '[class*="close-button"]',
      '[class*="close-modal"]',
      '[class*="dismiss"]',
      ".modal-header button.close",
      ".dialog-close",
      '[data-dismiss="modal"]',
      "button.close-btn",
      '[aria-label="close"]'
    ].freeze

    # Overlay/backdrop selectors that might block clicks
    OVERLAY_SELECTORS = [
      ".modal-backdrop",
      ".overlay",
      ".popup-overlay",
      '[class*="backdrop"]'
    ].freeze

    attr_reader :browser, :session_id

    def initialize(browser:, session_id:)
      @browser = browser
      @session_id = session_id
    end

    # Clean the page by dismissing all obstacles
    # @return [Hash] Summary of actions taken
    def clean!
      actions_taken = []

      # Handle cookie consent first (most common blocker)
      if dismiss_cookie_consent
        actions_taken << "dismissed_cookie_consent"
        sleep(0.5) # Wait for animations
      end

      # Handle any modal/popup
      if dismiss_popups
        actions_taken << "dismissed_popup"
        sleep(0.5)
      end

      # Try to remove overlays that might block clicks
      if remove_overlays
        actions_taken << "removed_overlays"
      end

      {
        success: true,
        actions_taken: actions_taken
      }
    rescue => e
      Rails.logger.warn "[PageCleaner] Error cleaning page: #{e.message}"
      { success: false, error: e.message }
    end

    # Dismiss cookie consent banners
    # @return [Boolean] Whether consent was dismissed
    def dismiss_cookie_consent
      COOKIE_CONSENT_SELECTORS.each do |selector|
        if click_if_visible(selector)
          Rails.logger.info "[PageCleaner] Dismissed cookie consent using: #{selector}"
          return true
        end
      end
      false
    end

    # Dismiss any popup modals
    # @return [Boolean] Whether a popup was dismissed
    def dismiss_popups
      POPUP_CLOSE_SELECTORS.each do |selector|
        if click_if_visible(selector)
          Rails.logger.info "[PageCleaner] Dismissed popup using: #{selector}"
          return true
        end
      end
      false
    end

    # Remove overlay elements that might block clicks
    # @return [Boolean] Whether overlays were removed
    def remove_overlays
      script = <<~JS
        (function() {
          const overlays = document.querySelectorAll('.modal-backdrop, .overlay, [class*="backdrop"]');
          overlays.forEach(el => {
            el.style.display = 'none';
            el.style.pointerEvents = 'none';
          });
          return overlays.length > 0;
        })()
      JS

      result = @browser.evaluate(@session_id, script)
      result == true
    rescue => e
      Rails.logger.debug "[PageCleaner] Failed to remove overlays: #{e.message}"
      false
    end

    # Check if page has visible obstacles
    # @return [Boolean] True if obstacles detected
    def has_obstacles?
      has_cookie_banner? || has_popup?
    end

    # Check for visible cookie banner
    def has_cookie_banner?
      COOKIE_CONSENT_SELECTORS.any? { |selector| element_visible?(selector) }
    end

    # Check for visible popup
    def has_popup?
      POPUP_CLOSE_SELECTORS.any? { |selector| element_visible?(selector) }
    end

    private

    # Check if selector uses Playwright-specific syntax
    def playwright_selector?(selector)
      selector.include?(":has-text") || selector.include?(":text(") || selector.include?(":contains")
    end

    # Click element if it's visible
    # For Playwright selectors, just try to click with a short timeout
    def click_if_visible(selector)
      if playwright_selector?(selector)
        # For Playwright selectors, try clicking directly with short timeout
        result = @browser.perform_action(
          @session_id,
          action: :click,
          selector: selector,
          timeout: 2000
        )
        return result[:success] != false
      end

      # For standard CSS selectors, check visibility first
      return false unless element_visible?(selector)

      result = @browser.perform_action(
        @session_id,
        action: :click,
        selector: selector,
        timeout: 3000
      )
      result[:success] != false
    rescue => e
      Rails.logger.debug "[PageCleaner] Click failed for #{selector}: #{e.message}"
      false
    end

    # Check if element is visible on page (standard CSS selectors only)
    def element_visible?(selector)
      # Skip visibility check for Playwright selectors - they can't be used with querySelector
      return true if playwright_selector?(selector)

      script = <<~JS
        (function() {
          try {
            const el = document.querySelector('#{selector.gsub("'", "\\\\'")}');
            if (!el) return false;
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            return rect.width > 0 &&
                   rect.height > 0 &&
                   style.display !== 'none' &&
                   style.visibility !== 'hidden' &&
                   style.opacity !== '0';
          } catch(e) {
            return false;
          }
        })()
      JS

      result = @browser.evaluate(@session_id, script)
      result == true
    rescue => e
      Rails.logger.debug "[PageCleaner] Visibility check failed for #{selector}: #{e.message}"
      false
    end
  end
end
