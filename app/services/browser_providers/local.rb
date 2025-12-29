# frozen_string_literal: true

require "playwright"

module BrowserProviders
  # Local Playwright browser provider
  # Wraps the existing BrowserPool for AI task execution
  class Local < Base
    # Thread-safe session storage
    @sessions = Concurrent::Map.new

    class << self
      attr_reader :sessions
    end

    def provider_name
      "local"
    end

    def local?
      true
    end

    def supports_cdp?
      true
    end

    def create_session(**options)
      session_id = SecureRandom.uuid
      viewport = options[:viewport] || { width: 1280, height: 720 }
      # Ensure viewport has symbol keys
      viewport = viewport.symbolize_keys if viewport.respond_to?(:symbolize_keys)

      log_action(:create_session, session_id: session_id, viewport: viewport)

      # Create playwright instance and browser context
      # Note: Playwright.create returns an Execution object, use .playwright for the API
      execution = ::Playwright.create(playwright_cli_executable_path: find_playwright_path)
      playwright = execution.playwright

      browser_type = options[:browser]&.to_sym || :chromium

      browser = playwright.send(browser_type).launch(
        headless: options.fetch(:headless, true),
        args: ["--no-sandbox", "--disable-setuid-sandbox"]
      )

      context_options = {
        viewport: { width: viewport[:width].to_i, height: viewport[:height].to_i }
      }
      context_options[:deviceScaleFactor] = options[:device_scale_factor] if options[:device_scale_factor]
      context_options[:isMobile] = options[:is_mobile] if options[:is_mobile]
      context_options[:hasTouch] = options[:has_touch] if options[:has_touch]
      context_options[:userAgent] = options[:user_agent] if options[:user_agent]

      context = browser.new_context(**context_options)

      page = context.new_page

      # Store session data (keep execution to properly stop later)
      session_data = {
        execution: execution,
        playwright: playwright,
        browser: browser,
        context: context,
        page: page,
        created_at: Time.current
      }

      self.class.sessions[session_id] = session_data

      {
        session_id: session_id,
        provider: "local"
      }
    rescue => e
      log_error(:create_session, e)
      raise
    end

    def close_session(session_id)
      log_action(:close_session, session_id: session_id)

      session = self.class.sessions.delete(session_id)
      return unless session

      session[:page]&.close rescue nil
      session[:context]&.close rescue nil
      session[:browser]&.close rescue nil
      session[:execution]&.stop rescue nil
    end

    def navigate(session_id, url)
      page = get_page(session_id)
      log_action(:navigate, session_id: session_id, url: url)

      page.goto(url, waitUntil: "networkidle")

      # Wait for any remaining JavaScript to finish rendering
      page.wait_for_load_state("networkidle")
      sleep(1) # Brief extra wait for late-loading dynamic content

      {
        url: page.url,
        title: page.title
      }
    rescue => e
      log_error(:navigate, e)
      { url: url, title: nil, error: e.message }
    end

    def perform_action(session_id, action:, selector: nil, value: nil, **options)
      page = get_page(session_id)
      log_action(:perform_action, session_id: session_id, action: action, selector: selector)

      case action.to_sym
      when :click_at, :click_coordinates
        # Coordinate-based clicking - click at specific x,y position
        x = options[:x] || value&.dig(:x) || (value.is_a?(Array) ? value[0] : nil)
        y = options[:y] || value&.dig(:y) || (value.is_a?(Array) ? value[1] : nil)
        raise ArgumentError, "click_at requires x and y coordinates" unless x && y

        Rails.logger.info "[Local] Clicking at coordinates: (#{x}, #{y})"
        page.mouse.click(x.to_f, y.to_f)
      when :click
        # Check if coordinates are provided (preferred method)
        if options[:x] && options[:y]
          Rails.logger.info "[Local] Clicking at coordinates: (#{options[:x]}, #{options[:y]})"
          page.mouse.click(options[:x].to_f, options[:y].to_f)
        elsif selector.present?
          # Fallback: Scroll element into view first to improve reliability
          scroll_into_view_if_needed(page, selector)
          page.click(selector, **options.slice(:timeout, :button, :modifiers, :position))
        else
          raise ArgumentError, "click requires either coordinates (x, y) or a selector"
        end
      when :type
        page.type(selector, value.to_s, **options.slice(:timeout, :delay))
      when :fill
        page.fill(selector, value.to_s, **options.slice(:timeout))
      when :hover
        page.hover(selector, **options.slice(:timeout, :position))
      when :scroll
        scroll_amount = case value.to_s.downcase
        when "down", "body" then 400  # Reduced from 800 for smoother scrolling
        when "up" then -400
        when "bottom" then "document.body.scrollHeight"
        when "top" then 0
        when "page_down" then "window.innerHeight * 0.7"  # Reduced from 0.9 for overlap
        when "page_up" then "-(window.innerHeight * 0.7)"
        else
          # If the value is a number or empty, default to scrolling down
          amount = value.to_i
          amount == 0 ? 400 : amount
        end

        if scroll_amount.is_a?(String)
          if scroll_amount.include?("scrollHeight")
            page.evaluate("window.scrollTo(0, #{scroll_amount})")
          else
            page.evaluate("window.scrollBy(0, #{scroll_amount})")
          end
        elsif value.is_a?(Hash)
          page.evaluate("window.scrollTo(#{value[:x] || 0}, #{value[:y] || 0})")
        else
          page.evaluate("window.scrollBy(0, #{scroll_amount})")
        end
      when :scroll_into_view
        page.evaluate("document.querySelector('#{selector}')?.scrollIntoView({behavior: 'smooth', block: 'center'})")
      when :select
        page.select_option(selector, value)
      when :wait
        sleep(value.to_f / 1000)
      when :press
        page.keyboard.press(value.to_s)
      when :focus
        page.focus(selector)
      when :clear
        page.fill(selector, "")
      else
        raise ArgumentError, "Unknown action: #{action}"
      end

      { success: true, url: page.url }
    rescue => e
      log_error(:perform_action, e)
      { success: false, error: e.message, url: page&.url }
    end

    def screenshot(session_id, **options)
      page = get_page(session_id)
      log_action(:screenshot, session_id: session_id, options: options)

      data = page.screenshot(
        fullPage: options.fetch(:full_page, true),
        type: "png"
      )

      {
        data: data,
        content_type: "image/png"
      }
    rescue => e
      log_error(:screenshot, e)
      raise
    end

    def page_content(session_id, format: :html)
      page = get_page(session_id)
      log_action(:page_content, session_id: session_id, format: format)

      case format
      when :html
        page.content
      when :text
        page.evaluate("document.body.innerText")
      when :accessibility
        page.accessibility.snapshot
      else
        raise ArgumentError, "Unknown format: #{format}"
      end
    rescue => e
      log_error(:page_content, e)
      raise
    end

    def current_url(session_id)
      get_page(session_id).url
    end

    def current_title(session_id)
      get_page(session_id).title
    end

    # Extract interactive elements with their bounding boxes for AI reference
    # Returns elements with refs like BTN1, IN1, LNK1 and their coordinates
    def extract_elements_with_refs(session_id)
      page = get_page(session_id)
      viewport = page.viewport_size

      elements = []
      counters = { btn: 0, in: 0, lnk: 0, chk: 0, sel: 0, other: 0 }

      # JavaScript to extract all interactive elements with their bounding boxes
      script = <<~JS
        (() => {
          const results = [];
          // Expanded selectors to catch custom checkboxes, toggles, and interactive elements
          const selectors = [
            'a', 'button', 'input', 'select', 'textarea',
            '[role="button"]', '[role="checkbox"]', '[role="switch"]', '[role="link"]', '[role="menuitem"]',
            '[onclick]', '[data-action]', '[data-toggle]',
            '[class*="btn"]', '[class*="button"]', '[class*="checkbox"]', '[class*="toggle"]', '[class*="check"]',
            'label[for]', 'label.checkbox', 'label.toggle',
            '.clickable', '.interactive', '.selectable',
            'span[onclick]', 'div[onclick]', 'li[onclick]',
            // Common custom checkbox patterns
            '.form-check', '.custom-checkbox', '.custom-control',
            'i.fa-check', 'i.fa-square', 'i.fa-check-square',
            // Brickset-specific patterns
            '.tags li', '.actionlist li', '.want', '.own', '.have'
          ].join(', ');

          const elements = document.querySelectorAll(selectors);

          elements.forEach((el, idx) => {
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);

            // Skip hidden or off-screen elements
            if (rect.width === 0 || rect.height === 0) return;
            if (style.display === 'none' || style.visibility === 'hidden') return;
            if (rect.bottom < 0 || rect.top > window.innerHeight) return;
            if (rect.right < 0 || rect.left > window.innerWidth) return;

            // Get text content
            let text = el.innerText || el.value || el.placeholder || el.getAttribute('aria-label') || el.title || '';
            text = text.trim().substring(0, 50);

            // Determine element type
            const tag = el.tagName.toLowerCase();
            const type = el.type || '';
            const role = el.getAttribute('role') || '';
            const classList = el.classList ? el.classList.toString().toLowerCase() : '';
            const id = (el.id || '').toLowerCase();

            let elementType = 'other';

            // Check for checkbox-like elements (including custom implementations)
            const isCheckboxLike = (
              role === 'checkbox' ||
              role === 'switch' ||
              (tag === 'input' && type === 'checkbox') ||
              classList.includes('checkbox') ||
              classList.includes('check') ||
              classList.includes('toggle') ||
              classList.includes('own') ||
              classList.includes('want') ||
              classList.includes('have') ||
              id.includes('own') ||
              id.includes('want') ||
              text.toLowerCase().includes('own') ||
              text.toLowerCase().includes('want')
            );

            if (isCheckboxLike) {
              elementType = 'checkbox';
            } else if (tag === 'button' || role === 'button' || classList.includes('btn')) {
              elementType = 'button';
            } else if (tag === 'a' || role === 'link') {
              elementType = 'link';
            } else if (tag === 'input' || tag === 'textarea') {
              elementType = 'input';
            } else if (tag === 'select') {
              elementType = 'select';
            }

            // Check if element appears "checked" or "active"
            const isChecked = el.checked ||
              classList.includes('active') ||
              classList.includes('checked') ||
              classList.includes('selected') ||
              el.getAttribute('aria-checked') === 'true';

            results.push({
              tag: tag,
              type: type,
              elementType: elementType,
              text: text,
              x: Math.round(rect.left + rect.width / 2),
              y: Math.round(rect.top + rect.height / 2),
              width: Math.round(rect.width),
              height: Math.round(rect.height),
              id: el.id || null,
              className: el.className ? el.className.toString().substring(0, 50) : null,
              checked: isChecked
            });
          });

          return results;
        })()
      JS

      raw_elements = page.evaluate(script)

      # Assign refs and build final list
      raw_elements.each do |el|
        # Generate ref based on element type
        ref = case el["elementType"]
        when "button"
          counters[:btn] += 1
          "BTN#{counters[:btn]}"
        when "input"
          counters[:in] += 1
          "IN#{counters[:in]}"
        when "link"
          counters[:lnk] += 1
          "LNK#{counters[:lnk]}"
        when "checkbox"
          counters[:chk] += 1
          "CHK#{counters[:chk]}"
        when "select"
          counters[:sel] += 1
          "SEL#{counters[:sel]}"
        else
          counters[:other] += 1
          "EL#{counters[:other]}"
        end

        elements << {
          ref: ref,
          type: el["elementType"],
          tag: el["tag"],
          text: el["text"],
          x: el["x"],
          y: el["y"],
          width: el["width"],
          height: el["height"],
          id: el["id"],
          class: el["className"],
          checked: el["checked"]
        }
      end

      {
        elements: elements,
        viewport: viewport
      }
    rescue => e
      log_error(:extract_elements_with_refs, e)
      { elements: [], viewport: { width: 1280, height: 720 } }
    end

    def evaluate(session_id, script)
      page = get_page(session_id)
      log_action(:evaluate, session_id: session_id, script_length: script.length)

      page.evaluate(script)
    rescue => e
      log_error(:evaluate, e)
      raise
    end

    def wait_for_selector(session_id, selector, timeout: 30_000)
      page = get_page(session_id)
      log_action(:wait_for_selector, session_id: session_id, selector: selector)

      page.wait_for_selector(selector, timeout: timeout)
    rescue => e
      log_error(:wait_for_selector, e)
      raise
    end

    def wait_for_navigation(session_id, **options)
      page = get_page(session_id)
      log_action(:wait_for_navigation, session_id: session_id)

      page.wait_for_navigation(**options)
    rescue => e
      log_error(:wait_for_navigation, e)
      raise
    end

    def session_alive?(session_id)
      session = self.class.sessions[session_id]
      return false unless session

      # Try to access the page to verify it's still alive
      session[:page]&.url
      true
    rescue
      false
    end

    # CDP methods for advanced control
    def cdp_session(session_id)
      session = self.class.sessions[session_id]
      raise "Session not found: #{session_id}" unless session

      @cdp_sessions ||= {}
      @cdp_sessions[session_id] ||= session[:context].new_cdp_session(session[:page])
    end

    def cdp_send(session_id, method, params = {})
      cdp = cdp_session(session_id)
      cdp.send_message(method, params)
    end

    private

    def get_page(session_id)
      session = self.class.sessions[session_id]
      raise "Session not found: #{session_id}" unless session

      session[:page]
    end

    def find_playwright_path
      paths = [
        "npx playwright",
        "/usr/local/bin/npx playwright",
        File.join(ENV["HOME"], ".npm-global/bin/npx playwright")
      ]

      paths.find { |path| system("which #{path.split.first} > /dev/null 2>&1") } || "npx playwright"
    end

    # Scroll element into view if it's not visible
    # Uses Playwright's native locator to handle special selectors like :has-text()
    def scroll_into_view_if_needed(page, selector)
      # Skip non-standard selectors that might cause issues with scrolling
      # Playwright will handle scrolling automatically on click if needed
      return if selector.include?(":has-text") || selector.include?(":text") || selector.include?(":contains")

      # Only use querySelector for standard CSS selectors
      page.evaluate(<<~JS)
        (function() {
          try {
            const el = document.querySelector('#{selector.gsub("'", "\\\\'")}');
            if (el) {
              const rect = el.getBoundingClientRect();
              const isInView = rect.top >= 0 && rect.bottom <= window.innerHeight;
              if (!isInView) {
                el.scrollIntoView({ behavior: 'instant', block: 'center' });
              }
            }
          } catch(e) {
            // Ignore selector errors - Playwright will handle the click
          }
        })()
      JS
    rescue => e
      Rails.logger.debug "[Local] scroll_into_view_if_needed failed: #{e.message}"
    end
  end
end
