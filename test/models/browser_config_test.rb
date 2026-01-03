# frozen_string_literal: true

require "test_helper"

class BrowserConfigTest < ActiveSupport::TestCase
  # ============================================
  # Validations
  # ============================================

  test "validates presence of browser" do
    config = BrowserConfig.new(project: projects(:main_project), name: "Test", width: 1280, height: 720)
    assert_not config.valid?
    assert_includes config.errors[:browser], "can't be blank"
  end

  test "validates browser is in allowed values" do
    project = projects(:main_project)

    %w[chromium firefox webkit].each do |valid_browser|
      config = BrowserConfig.new(
        project: project,
        browser: valid_browser,
        name: "Test",
        width: 1280,
        height: 720
      )
      assert config.valid?, "Expected browser '#{valid_browser}' to be valid"
    end
  end

  test "rejects invalid browser" do
    config = BrowserConfig.new(
      project: projects(:main_project),
      browser: "safari",
      name: "Test",
      width: 1280,
      height: 720
    )
    assert_not config.valid?
    assert_includes config.errors[:browser], "is not included in the list"
  end

  test "validates presence of name" do
    config = BrowserConfig.new(
      project: projects(:main_project),
      browser: "chromium",
      width: 1280,
      height: 720
    )
    assert_not config.valid?
    assert_includes config.errors[:name], "can't be blank"
  end

  test "validates presence of width" do
    config = BrowserConfig.new(
      project: projects(:main_project),
      browser: "chromium",
      name: "Test",
      height: 720
    )
    assert_not config.valid?
    assert_includes config.errors[:width], "can't be blank"
  end

  test "validates width is greater than 0" do
    config = BrowserConfig.new(
      project: projects(:main_project),
      browser: "chromium",
      name: "Test",
      width: 0,
      height: 720
    )
    assert_not config.valid?
    assert_includes config.errors[:width], "must be greater than 0"
  end

  test "validates presence of height" do
    config = BrowserConfig.new(
      project: projects(:main_project),
      browser: "chromium",
      name: "Test",
      width: 1280
    )
    assert_not config.valid?
    assert_includes config.errors[:height], "can't be blank"
  end

  test "validates height is greater than 0" do
    config = BrowserConfig.new(
      project: projects(:main_project),
      browser: "chromium",
      name: "Test",
      width: 1280,
      height: -100
    )
    assert_not config.valid?
    assert_includes config.errors[:height], "must be greater than 0"
  end

  # ============================================
  # Associations
  # ============================================

  test "belongs to project" do
    config = browser_configs(:chrome_desktop)
    assert_equal projects(:main_project), config.project
  end

  test "has many baselines" do
    config = browser_configs(:chrome_desktop)
    assert_respond_to config, :baselines
    assert config.baselines.count > 0
  end

  test "has many snapshots" do
    config = browser_configs(:chrome_desktop)
    assert_respond_to config, :snapshots
  end

  # ============================================
  # Scopes
  # ============================================

  test "enabled scope returns only enabled configs" do
    enabled = BrowserConfig.enabled
    enabled.each do |config|
      assert config.enabled
    end
  end

  # ============================================
  # Viewport Config
  # ============================================

  test "to_viewport_config returns correct hash for desktop" do
    config = browser_configs(:chrome_desktop)
    viewport = config.to_viewport_config

    assert_equal 1280, viewport[:width]
    assert_equal 720, viewport[:height]
    assert_equal 1.0, viewport[:device_scale_factor]
    assert_equal false, viewport[:is_mobile]
    assert_equal false, viewport[:has_touch]
    assert_not viewport.key?(:user_agent)
  end

  test "to_viewport_config returns correct hash for mobile" do
    config = browser_configs(:chrome_mobile)
    viewport = config.to_viewport_config

    assert_equal 375, viewport[:width]
    assert_equal 812, viewport[:height]
    assert_equal 2.0, viewport[:device_scale_factor]
    assert_equal true, viewport[:is_mobile]
    assert_equal true, viewport[:has_touch]
  end

  test "to_viewport_config includes user_agent when present" do
    config = browser_configs(:chrome_desktop)
    config.user_agent = "Custom User Agent"

    viewport = config.to_viewport_config

    assert_equal "Custom User Agent", viewport[:user_agent]
  end

  # ============================================
  # Display Name
  # ============================================

  test "display_name combines name and resolution" do
    config = browser_configs(:chrome_desktop)
    expected = "Chrome Desktop (1280x720)"

    assert_equal expected, config.display_name
  end

  test "display_name for mobile config" do
    config = browser_configs(:chrome_mobile)
    expected = "Chrome Mobile (375x812)"

    assert_equal expected, config.display_name
  end
end
