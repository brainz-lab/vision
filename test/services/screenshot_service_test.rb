# frozen_string_literal: true

require "test_helper"

class ScreenshotServiceTest < ActiveSupport::TestCase
  # ============================================
  # Test Doubles
  # ============================================

  class MockBrowserPage
    attr_accessor :url, :actions_performed, :evaluated_scripts

    def initialize
      @url = nil
      @actions_performed = []
      @evaluated_scripts = []
    end

    def goto(url, **options)
      @url = url
      @actions_performed << { type: "goto", url: url, options: options }
    end

    def wait_for_selector(selector, **options)
      @actions_performed << { type: "wait_for_selector", selector: selector, options: options }
    end

    def click(selector)
      @actions_performed << { type: "click", selector: selector }
    end

    def fill(selector, text)
      @actions_performed << { type: "fill", selector: selector, text: text }
    end

    def hover(selector)
      @actions_performed << { type: "hover", selector: selector }
    end

    def select_option(selector, value)
      @actions_performed << { type: "select_option", selector: selector, value: value }
    end

    def evaluate(script)
      @evaluated_scripts << script

      # Return mock dimensions for get_page_dimensions
      if script.include?("scrollWidth")
        { "width" => 1280, "height" => 2400 }
      else
        nil
      end
    end

    def screenshot(**options)
      @actions_performed << { type: "screenshot", options: options }
      # Return mock PNG data (1x1 white pixel PNG)
      create_mock_png
    end

    private

    def create_mock_png
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.png")
        MiniMagick::Tool::Convert.new do |convert|
          convert.size("100x100")
          convert.xc("white")
          convert << path
        end
        File.binread(path)
      end
    end
  end

  # ============================================
  # Initialization
  # ============================================

  test "initializes with Page and browser_config" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)

    service = ScreenshotService.new(page, browser_config: browser_config)

    assert_equal page, service.page
    assert_equal browser_config, service.browser_config
    assert_equal page.project, service.project
  end

  test "initializes with Snapshot" do
    snapshot = snapshots(:pending_snapshot)

    service = ScreenshotService.new(snapshot)

    assert_equal snapshot.page, service.page
    assert_equal snapshot.browser_config, service.browser_config
    assert_equal snapshot.project, service.project
  end

  # ============================================
  # URL Determination
  # ============================================

  test "uses full_url for production environment" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)

    service = ScreenshotService.new(page, browser_config: browser_config)

    # Access private method for testing
    url = service.send(:determine_url)

    assert_equal page.full_url, url
  end

  test "uses staging_url for staging environment snapshot" do
    snapshot = snapshots(:staging_snapshot)
    service = ScreenshotService.new(snapshot)

    url = service.send(:determine_url)

    assert_equal snapshot.page.staging_url, url
  end

  # ============================================
  # Action Execution (Unit Tests)
  # ============================================

  test "execute_action handles click action" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)
    service = ScreenshotService.new(page, browser_config: browser_config)
    mock_page = MockBrowserPage.new

    action = { "type" => "click", "selector" => ".button" }
    service.send(:execute_action, mock_page, action)

    click_action = mock_page.actions_performed.find { |a| a[:type] == "click" }
    assert_not_nil click_action
    assert_equal ".button", click_action[:selector]
  end

  test "execute_action handles scroll action" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)
    service = ScreenshotService.new(page, browser_config: browser_config)
    mock_page = MockBrowserPage.new

    action = { "type" => "scroll", "y" => 500 }
    service.send(:execute_action, mock_page, action)

    # Scroll is done via evaluate
    assert mock_page.evaluated_scripts.any? { |s| s.include?("scrollTo") && s.include?("500") }
  end

  test "execute_action handles wait action" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)
    service = ScreenshotService.new(page, browser_config: browser_config)
    mock_page = MockBrowserPage.new

    # Wait action uses sleep, so just verify it doesn't error
    action = { "type" => "wait", "ms" => 100 }
    assert_nothing_raised do
      service.send(:execute_action, mock_page, action)
    end
  end

  test "execute_action handles fill action" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)
    service = ScreenshotService.new(page, browser_config: browser_config)
    mock_page = MockBrowserPage.new

    action = { "type" => "fill", "selector" => "#input", "text" => "test value" }
    service.send(:execute_action, mock_page, action)

    fill_action = mock_page.actions_performed.find { |a| a[:type] == "fill" }
    assert_not_nil fill_action
    assert_equal "#input", fill_action[:selector]
    assert_equal "test value", fill_action[:text]
  end

  test "execute_action handles hover action" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)
    service = ScreenshotService.new(page, browser_config: browser_config)
    mock_page = MockBrowserPage.new

    action = { "type" => "hover", "selector" => ".menu" }
    service.send(:execute_action, mock_page, action)

    hover_action = mock_page.actions_performed.find { |a| a[:type] == "hover" }
    assert_not_nil hover_action
    assert_equal ".menu", hover_action[:selector]
  end

  test "execute_action handles select action" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)
    service = ScreenshotService.new(page, browser_config: browser_config)
    mock_page = MockBrowserPage.new

    action = { "type" => "select", "selector" => "#dropdown", "value" => "option1" }
    service.send(:execute_action, mock_page, action)

    select_action = mock_page.actions_performed.find { |a| a[:type] == "select_option" }
    assert_not_nil select_action
    assert_equal "#dropdown", select_action[:selector]
    assert_equal "option1", select_action[:value]
  end

  # ============================================
  # Element Modifications
  # ============================================

  test "apply_element_modifications hides elements" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)
    service = ScreenshotService.new(page, browser_config: browser_config)
    mock_page = MockBrowserPage.new

    service.send(:apply_element_modifications, mock_page)

    # Check that hide selectors were applied
    hide_scripts = mock_page.evaluated_scripts.select { |s| s.include?("visibility") }
    assert hide_scripts.any?
  end

  test "apply_element_modifications masks elements" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)
    service = ScreenshotService.new(page, browser_config: browser_config)
    mock_page = MockBrowserPage.new

    service.send(:apply_element_modifications, mock_page)

    # Check that mask selectors were applied
    mask_scripts = mock_page.evaluated_scripts.select { |s| s.include?("background") }
    assert mask_scripts.any?
  end

  # ============================================
  # Selector Escaping
  # ============================================

  test "escapes single quotes in selectors" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)
    service = ScreenshotService.new(page, browser_config: browser_config)

    escaped = service.send(:escape_selector, "[data-value='test']")
    assert_equal "[data-value=\\'test\\']", escaped
  end

  # ============================================
  # Thumbnail Creation
  # ============================================

  test "create_thumbnail resizes image" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)
    service = ScreenshotService.new(page, browser_config: browser_config)

    # Create a test image
    original_data = create_test_image(1280, 2400)
    thumbnail_data = service.send(:create_thumbnail, original_data)

    # Parse thumbnail
    thumbnail = MiniMagick::Image.read(thumbnail_data)

    assert_equal 400, thumbnail.width
    # Height should be proportionally scaled
    assert thumbnail.height < 2400
  end

  # ============================================
  # Helper Methods
  # ============================================

  def create_test_image(width, height, color = "white")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.png")

      MiniMagick::Tool::Convert.new do |convert|
        convert.size("#{width}x#{height}")
        convert.xc(color)
        convert << path
      end

      File.binread(path)
    end
  end
end
