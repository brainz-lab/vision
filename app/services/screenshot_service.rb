# ScreenshotService captures screenshots of web pages using Playwright.
# It handles navigation, waiting, element hiding/masking, and storage.

class ScreenshotService
  attr_reader :page, :browser_config, :project

  def initialize(page_or_snapshot, browser_config: nil)
    if page_or_snapshot.is_a?(Snapshot)
      @snapshot = page_or_snapshot
      @page = page_or_snapshot.page
      @browser_config = page_or_snapshot.browser_config
    else
      @page = page_or_snapshot
      @browser_config = browser_config
      @snapshot = nil
    end

    @project = @page.project
  end

  def capture
    started_at = Time.current

    BrowserPool.with_browser(@browser_config) do |browser_page|
      # Navigate to page
      url = determine_url
      browser_page.goto(url, wait_until: 'networkidle')

      # Wait for page readiness
      wait_for_ready(browser_page)

      # Execute pre-capture actions
      execute_actions(browser_page)

      # Hide/mask elements
      apply_element_modifications(browser_page)

      # Capture screenshot
      screenshot_data = browser_page.screenshot(full_page: true, type: 'png')

      # Calculate dimensions
      dimensions = get_page_dimensions(browser_page)

      # Store the screenshot
      store_screenshot(screenshot_data, dimensions, started_at)
    end
  end

  private

  def determine_url
    @snapshot&.environment == 'staging' ? @page.staging_url : @page.full_url
  end

  def wait_for_ready(browser_page)
    # Wait for network idle (already done in goto)

    # Custom wait selector
    if @page.wait_for.present?
      selector = @page.wait_for['selector']
      timeout = @page.wait_for['timeout'] || 10_000
      browser_page.wait_for_selector(selector, timeout: timeout) rescue nil
    end

    # Additional wait time
    wait_ms = @page.effective_wait_ms
    sleep(wait_ms / 1000.0) if wait_ms.positive?
  end

  def execute_actions(browser_page)
    @page.all_actions.each do |action|
      execute_action(browser_page, action)
    end
  end

  def execute_action(browser_page, action)
    case action['type']
    when 'click'
      browser_page.click(action['selector']) rescue nil
    when 'scroll'
      browser_page.evaluate("window.scrollTo(0, #{action['y']})")
    when 'wait'
      sleep(action['ms'] / 1000.0)
    when 'type', 'fill'
      browser_page.fill(action['selector'], action['text']) rescue nil
    when 'hover'
      browser_page.hover(action['selector']) rescue nil
    when 'select'
      browser_page.select_option(action['selector'], action['value']) rescue nil
    end
  end

  def apply_element_modifications(browser_page)
    # Hide elements (set visibility: hidden)
    @page.effective_hide_selectors.each do |selector|
      browser_page.evaluate(<<~JS)
        document.querySelectorAll('#{escape_selector(selector)}').forEach(el => {
          el.style.visibility = 'hidden';
        });
      JS
    rescue => e
      Rails.logger.warn "Failed to hide selector #{selector}: #{e.message}"
    end

    # Mask elements (replace with solid color)
    @page.effective_mask_selectors.each do |selector|
      browser_page.evaluate(<<~JS)
        document.querySelectorAll('#{escape_selector(selector)}').forEach(el => {
          el.style.background = '#8B5CF6';
          el.innerHTML = '';
        });
      JS
    rescue => e
      Rails.logger.warn "Failed to mask selector #{selector}: #{e.message}"
    end
  end

  def escape_selector(selector)
    selector.gsub("'", "\\'")
  end

  def get_page_dimensions(browser_page)
    browser_page.evaluate(<<~JS)
      ({
        width: document.documentElement.scrollWidth,
        height: document.documentElement.scrollHeight
      })
    JS
  end

  def store_screenshot(screenshot_data, dimensions, started_at)
    duration_ms = ((Time.current - started_at) * 1000).to_i

    # Create thumbnail
    thumbnail_data = create_thumbnail(screenshot_data)

    if @snapshot
      # Update existing snapshot
      @snapshot.screenshot.attach(
        io: StringIO.new(screenshot_data),
        filename: "screenshot_#{@snapshot.id}.png",
        content_type: 'image/png'
      )

      @snapshot.thumbnail.attach(
        io: StringIO.new(thumbnail_data),
        filename: "thumbnail_#{@snapshot.id}.png",
        content_type: 'image/png'
      )

      @snapshot.update!(
        status: 'captured',
        captured_at: Time.current,
        capture_duration_ms: duration_ms,
        width: dimensions['width'],
        height: dimensions['height'],
        file_size: screenshot_data.bytesize
      )

      @snapshot
    else
      # Create new snapshot
      snapshot = @page.snapshots.new(
        browser_config: @browser_config,
        status: 'captured',
        captured_at: Time.current,
        capture_duration_ms: duration_ms,
        width: dimensions['width'],
        height: dimensions['height'],
        file_size: screenshot_data.bytesize,
        triggered_by: 'api'
      )

      snapshot.screenshot.attach(
        io: StringIO.new(screenshot_data),
        filename: "screenshot_#{SecureRandom.uuid}.png",
        content_type: 'image/png'
      )

      snapshot.thumbnail.attach(
        io: StringIO.new(thumbnail_data),
        filename: "thumbnail_#{SecureRandom.uuid}.png",
        content_type: 'image/png'
      )

      snapshot.save!
      snapshot
    end
  end

  def create_thumbnail(screenshot_data)
    image = MiniMagick::Image.read(screenshot_data)
    image.resize('400x')
    image.to_blob
  end
end
