# frozen_string_literal: true

require "playwright"

# VisionWorker is a pre-warmed Playwright browser instance that implements
# the same interface as BrowserProviders::Local for compatibility with
# Ai::TaskExecutor and MCP tools.
#
# Workers are managed by VisionWorkerPool and reused across requests.
# After each task, the worker is reset (navigate to about:blank, clear cookies)
# to ensure clean state for the next task.
#
# The worker implements all methods required by TaskExecutor:
# - navigate(session_id, url)
# - perform_action(session_id, action:, ...)
# - screenshot(session_id, **options)
# - current_url(session_id)
# - current_title(session_id)
# - extract_elements_with_refs(session_id)
# - evaluate(session_id, script)
# - session_alive?(session_id)
#
class VisionWorker
  STALE_AFTER = 30.minutes
  DEFAULT_VIEWPORT = { width: 1280, height: 720 }.freeze

  attr_reader :session_id, :created_at

  def initialize
    @created_at = Time.current
    @mutex = Mutex.new
    @checked_out = false
    initialize_browser!
  end

  # === Pool management methods ===

  def checkout!
    @mutex.synchronize { @checked_out = true }
  end

  def checkin!
    @mutex.synchronize do
      reset!
      @checked_out = false
    end
  end

  def checked_out?
    @mutex.synchronize { @checked_out }
  end

  def healthy?
    @browser&.connected?
  rescue
    false
  end

  def stale?
    Time.current - @created_at > STALE_AFTER
  end

  def reinitialize!
    cleanup!
    @created_at = Time.current
    initialize_browser!
  end

  # === BrowserProviders::Base interface ===

  def provider_name
    "pool_worker"
  end

  def local?
    true
  end

  def supports_cdp?
    true
  end

  # For pooled workers, create_session just returns the existing session
  def create_session(**options)
    viewport = options[:viewport] || DEFAULT_VIEWPORT
    viewport = viewport.symbolize_keys if viewport.respond_to?(:symbolize_keys)

    # Reconfigure context viewport if different
    if viewport[:width] != @viewport[:width] || viewport[:height] != @viewport[:height]
      @page&.close rescue nil
      @context&.close rescue nil
      @context = @browser.new_context(viewport: { width: viewport[:width].to_i, height: viewport[:height].to_i })
      @page = @context.new_page
      @viewport = viewport
    end

    { session_id: @session_id, provider: "pool_worker" }
  end

  # For pooled workers, close_session just resets state
  def close_session(session_id)
    reset!
  end

  def navigate(session_id, url)
    log_action(:navigate, url: url)

    @page.goto(url, waitUntil: "networkidle")
    @page.wait_for_load_state(state: "networkidle")
    sleep(1) # Brief extra wait for dynamic content

    { url: @page.url, title: @page.title }
  rescue => e
    log_error(:navigate, e)
    { url: url, title: nil, error: e.message }
  end

  def perform_action(session_id, action:, selector: nil, value: nil, **options)
    log_action(:perform_action, action: action, selector: selector)

    case action.to_sym
    when :click_at, :click_coordinates
      x = options[:x] || value&.dig(:x) || (value.is_a?(Array) ? value[0] : nil)
      y = options[:y] || value&.dig(:y) || (value.is_a?(Array) ? value[1] : nil)
      raise ArgumentError, "click_at requires x and y coordinates" unless x && y
      @page.mouse.click(x.to_f, y.to_f)

    when :click
      if options[:x] && options[:y]
        @page.mouse.click(options[:x].to_f, options[:y].to_f)
      elsif selector.present?
        scroll_into_view_if_needed(selector)
        @page.click(selector, **options.slice(:timeout, :button, :modifiers, :position))
      else
        raise ArgumentError, "click requires either coordinates (x, y) or a selector"
      end

    when :type
      @page.type(selector, value.to_s, **options.slice(:timeout, :delay))

    when :fill
      @page.fill(selector, value.to_s, **options.slice(:timeout))

    when :hover
      @page.hover(selector, **options.slice(:timeout, :position))

    when :scroll
      scroll_amount = case value.to_s.downcase
      when "down", "body" then 400
      when "up" then -400
      when "bottom" then "document.body.scrollHeight"
      when "top" then 0
      when "page_down" then "window.innerHeight * 0.7"
      when "page_up" then "-(window.innerHeight * 0.7)"
      else
        amount = value.to_i
        amount == 0 ? 400 : amount
      end

      if scroll_amount.is_a?(String)
        if scroll_amount.include?("scrollHeight")
          @page.evaluate("window.scrollTo(0, #{scroll_amount})")
        else
          @page.evaluate("window.scrollBy(0, #{scroll_amount})")
        end
      elsif value.is_a?(Hash)
        @page.evaluate("window.scrollTo(#{value[:x] || 0}, #{value[:y] || 0})")
      else
        @page.evaluate("window.scrollBy(0, #{scroll_amount})")
      end

    when :scroll_into_view
      @page.evaluate("document.querySelector('#{selector}')?.scrollIntoView({behavior: 'smooth', block: 'center'})")

    when :select
      @page.select_option(selector, value)

    when :wait
      sleep(value.to_f / 1000)

    when :press
      @page.keyboard.press(value.to_s)

    when :focus
      @page.focus(selector)

    when :clear
      @page.fill(selector, "")

    else
      raise ArgumentError, "Unknown action: #{action}"
    end

    { success: true, url: @page.url }
  rescue => e
    log_error(:perform_action, e)
    { success: false, error: e.message, url: @page&.url }
  end

  def screenshot(session_id, **options)
    log_action(:screenshot, options: options)

    data = @page.screenshot(
      fullPage: options.fetch(:full_page, true),
      type: "png"
    )

    { data: data, content_type: "image/png" }
  rescue => e
    log_error(:screenshot, e)
    raise
  end

  def page_content(session_id, format: :html)
    case format
    when :html
      @page.content
    when :text
      @page.evaluate("document.body.innerText")
    when :accessibility
      @page.accessibility.snapshot
    else
      raise ArgumentError, "Unknown format: #{format}"
    end
  end

  def current_url(session_id)
    @page.url
  end

  def current_title(session_id)
    @page.title
  end

  def extract_elements_with_refs(session_id)
    viewport = @page.viewport_size

    script = <<~JS
      (() => {
        const results = [];
        const selectors = [
          'a', 'button', 'input', 'select', 'textarea',
          '[role="button"]', '[role="checkbox"]', '[role="switch"]', '[role="link"]', '[role="menuitem"]',
          '[onclick]', '[data-action]', '[data-toggle]',
          '[class*="btn"]', '[class*="button"]', '[class*="checkbox"]', '[class*="toggle"]', '[class*="check"]',
          'label[for]', 'label.checkbox', 'label.toggle',
          '.clickable', '.interactive', '.selectable',
          'span[onclick]', 'div[onclick]', 'li[onclick]',
          '.form-check', '.custom-checkbox', '.custom-control',
          'i.fa-check', 'i.fa-square', 'i.fa-check-square',
          '.tags li', '.actionlist li', '.want', '.own', '.have'
        ].join(', ');

        const elements = document.querySelectorAll(selectors);

        elements.forEach((el, idx) => {
          const rect = el.getBoundingClientRect();
          const style = window.getComputedStyle(el);

          if (rect.width === 0 || rect.height === 0) return;
          if (style.display === 'none' || style.visibility === 'hidden') return;
          if (rect.bottom < 0 || rect.top > window.innerHeight) return;
          if (rect.right < 0 || rect.left > window.innerWidth) return;

          let text = el.innerText || el.value || el.placeholder || el.getAttribute('aria-label') || el.title || '';
          text = text.trim().substring(0, 50);

          const tag = el.tagName.toLowerCase();
          const type = el.type || '';
          const role = el.getAttribute('role') || '';
          const classList = el.classList ? el.classList.toString().toLowerCase() : '';
          const id = (el.id || '').toLowerCase();

          let elementType = 'other';

          const isCheckboxLike = (
            role === 'checkbox' || role === 'switch' ||
            (tag === 'input' && type === 'checkbox') ||
            classList.includes('checkbox') || classList.includes('check') ||
            classList.includes('toggle') || classList.includes('own') ||
            classList.includes('want') || classList.includes('have') ||
            id.includes('own') || id.includes('want') ||
            text.toLowerCase().includes('own') || text.toLowerCase().includes('want')
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

          const isChecked = el.checked ||
            classList.includes('active') || classList.includes('checked') ||
            classList.includes('selected') || el.getAttribute('aria-checked') === 'true';

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

    raw_elements = @page.evaluate(script)
    counters = { btn: 0, in: 0, lnk: 0, chk: 0, sel: 0, other: 0 }
    elements = []

    raw_elements.each do |el|
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

    { elements: elements, viewport: viewport }
  rescue => e
    log_error(:extract_elements_with_refs, e)
    { elements: [], viewport: { width: 1280, height: 720 } }
  end

  def evaluate(session_id, script)
    log_action(:evaluate, script_length: script.length)
    @page.evaluate(script)
  end

  def wait_for_selector(session_id, selector, timeout: 30_000)
    @page.wait_for_selector(selector, timeout: timeout)
  end

  def wait_for_navigation(session_id, **options)
    @page.wait_for_navigation(**options)
  end

  def session_alive?(session_id)
    return false unless @session_id == session_id
    @browser&.connected? && @page&.url.present?
  rescue
    false
  end

  # === Cleanup methods ===

  def reset!
    @page.goto("about:blank") rescue nil
    @context.clear_cookies rescue nil
  end

  def cleanup!
    @page&.close rescue nil
    @context&.close rescue nil
    @browser&.close rescue nil
    @execution&.stop rescue nil
  end

  private

  def initialize_browser!
    @execution = ::Playwright.create(playwright_cli_executable_path: find_playwright_path)
    @playwright = @execution.playwright
    @browser = @playwright.chromium.launch(
      headless: true,
      args: [ "--no-sandbox", "--disable-setuid-sandbox" ]
    )
    @viewport = DEFAULT_VIEWPORT.dup
    @context = @browser.new_context(viewport: { width: @viewport[:width], height: @viewport[:height] })
    @page = @context.new_page
    @session_id = SecureRandom.uuid
    Rails.logger.info "[VisionWorker] Initialized worker #{@session_id}"
  end

  def find_playwright_path
    paths = [
      "npx playwright",
      "/usr/local/bin/npx playwright",
      File.join(ENV["HOME"], ".npm-global/bin/npx playwright")
    ]
    paths.find { |path| system("which #{path.split.first} > /dev/null 2>&1") } || "npx playwright"
  end

  def scroll_into_view_if_needed(selector)
    return if selector.include?(":has-text") || selector.include?(":text") || selector.include?(":contains")

    @page.evaluate(<<~JS)
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
        } catch(e) {}
      })()
    JS
  rescue => e
    Rails.logger.debug "[VisionWorker] scroll_into_view_if_needed failed: #{e.message}"
  end

  def log_action(action, **details)
    Rails.logger.debug "[VisionWorker:#{@session_id[0..7]}] #{action}: #{details}"
  end

  def log_error(action, error)
    Rails.logger.error "[VisionWorker:#{@session_id[0..7]}] #{action} failed: #{error.message}"
  end
end
