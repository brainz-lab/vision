# frozen_string_literal: true

require "test_helper"

class PageTest < ActiveSupport::TestCase
  # ============================================
  # Validations
  # ============================================

  test "validates presence of name" do
    page = Page.new(project: projects(:main_project), path: "/test", slug: "test")
    assert_not page.valid?
    assert_includes page.errors[:name], "can't be blank"
  end

  test "validates presence of path" do
    page = Page.new(project: projects(:main_project), name: "Test", slug: "test")
    assert_not page.valid?
    assert_includes page.errors[:path], "can't be blank"
  end

  test "validates presence of slug" do
    page = Page.new(project: projects(:main_project), name: "Test", path: "/test")
    # Slug should be auto-generated from name
    assert page.valid?
    assert_equal "test", page.slug
  end

  test "validates uniqueness of slug within project" do
    existing = pages(:homepage)
    page = Page.new(
      project: existing.project,
      name: "Duplicate",
      path: "/duplicate",
      slug: existing.slug
    )
    assert_not page.valid?
    assert_includes page.errors[:slug], "has already been taken"
  end

  test "allows same slug in different projects" do
    page = Page.new(
      project: projects(:secondary_project),
      name: "Homepage",
      path: "/",
      slug: "homepage"
    )
    assert page.valid?
  end

  # ============================================
  # Associations
  # ============================================

  test "belongs to project" do
    page = pages(:homepage)
    assert_equal projects(:main_project), page.project
  end

  test "has many baselines" do
    page = pages(:homepage)
    assert_respond_to page, :baselines
    assert page.baselines.count > 0
  end

  test "has many snapshots" do
    page = pages(:homepage)
    assert_respond_to page, :snapshots
  end

  test "has one latest_snapshot" do
    page = pages(:homepage)
    assert_respond_to page, :latest_snapshot
  end

  # ============================================
  # Scopes
  # ============================================

  test "enabled scope returns only enabled pages" do
    enabled = Page.enabled
    enabled.each do |page|
      assert page.enabled
    end
  end

  test "ordered scope orders by position" do
    pages = Page.ordered
    positions = pages.map(&:position)
    assert_equal positions.sort, positions
  end

  # ============================================
  # Callbacks
  # ============================================

  test "generates slug from name before validation" do
    page = Page.new(
      project: projects(:main_project),
      name: "My New Page",
      path: "/my-new-page"
    )

    page.valid?
    assert_equal "my-new-page", page.slug
  end

  test "does not override existing slug" do
    page = Page.new(
      project: projects(:main_project),
      name: "My Page",
      path: "/my-page",
      slug: "custom-slug"
    )

    page.valid?
    assert_equal "custom-slug", page.slug
  end

  # ============================================
  # URL Methods
  # ============================================

  test "full_url combines base_url and path" do
    page = pages(:homepage)
    expected = "https://example.com/"
    assert_equal expected, page.full_url
  end

  test "full_url with custom base" do
    page = pages(:login_page)
    assert_equal "https://custom.com/login", page.full_url("https://custom.com")
  end

  test "staging_url returns nil when no staging url configured" do
    page = pages(:secondary_home)
    assert_nil page.staging_url
  end

  test "staging_url returns staging url when configured" do
    page = pages(:homepage)
    assert_equal "https://staging.example.com/", page.staging_url
  end

  # ============================================
  # Baseline Methods
  # ============================================

  test "current_baseline returns active baseline for browser config and branch" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)

    baseline = page.current_baseline(browser_config, branch: "main")

    assert_not_nil baseline
    assert baseline.active
    assert_equal "main", baseline.branch
    assert_equal browser_config, baseline.browser_config
  end

  test "current_baseline returns nil when no matching baseline" do
    page = pages(:disabled_page)
    browser_config = browser_configs(:chrome_desktop)

    baseline = page.current_baseline(browser_config, branch: "main")
    assert_nil baseline
  end

  # ============================================
  # Effective Settings
  # ============================================

  test "effective_viewport returns page viewport if set" do
    page = Page.new(viewport: { "width" => 1920, "height" => 1080 })
    page.project = projects(:main_project)

    assert_equal({ "width" => 1920, "height" => 1080 }, page.effective_viewport)
  end

  test "effective_viewport falls back to project default" do
    page = pages(:homepage)
    page.viewport = nil

    assert_equal page.project.default_viewport, page.effective_viewport
  end

  test "effective_wait_ms returns page wait_ms if set" do
    page = pages(:homepage)
    page.wait_ms = 1000

    assert_equal 1000, page.effective_wait_ms
  end

  test "effective_wait_ms falls back to project default" do
    page = pages(:login_page)
    page.wait_ms = nil

    assert_equal page.project.wait_before_capture, page.effective_wait_ms
  end

  test "effective_hide_selectors combines page and project selectors" do
    page = pages(:homepage)
    combined = page.effective_hide_selectors

    assert_includes combined, ".cookie-banner"
  end

  test "effective_mask_selectors combines page and project selectors" do
    page = pages(:homepage)
    combined = page.effective_mask_selectors

    assert_includes combined, ".dynamic-timestamp"
  end

  test "all_actions returns empty array when no actions" do
    page = pages(:login_page)
    page.actions = nil

    assert_equal [], page.all_actions
  end

  test "all_actions returns actions array" do
    page = pages(:homepage)
    actions = page.all_actions

    assert_kind_of Array, actions
    assert actions.any?
  end
end
