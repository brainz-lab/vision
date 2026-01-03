# frozen_string_literal: true

require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  # ============================================
  # Validations
  # ============================================

  test "validates presence of platform_project_id" do
    project = Project.new(name: "Test", base_url: "https://example.com")
    assert_not project.valid?
    assert_includes project.errors[:platform_project_id], "can't be blank"
  end

  test "validates uniqueness of platform_project_id" do
    existing = projects(:main_project)
    project = Project.new(
      platform_project_id: existing.platform_project_id,
      name: "Duplicate",
      base_url: "https://example.com"
    )
    assert_not project.valid?
    assert_includes project.errors[:platform_project_id], "has already been taken"
  end

  test "validates presence of name" do
    project = Project.new(platform_project_id: "plt_new", base_url: "https://example.com")
    assert_not project.valid?
    assert_includes project.errors[:name], "can't be blank"
  end

  test "validates presence of base_url" do
    project = Project.new(platform_project_id: "plt_new", name: "Test")
    assert_not project.valid?
    assert_includes project.errors[:base_url], "can't be blank"
  end

  test "validates base_url format" do
    project = Project.new(
      platform_project_id: "plt_new",
      name: "Test",
      base_url: "not-a-url"
    )
    assert_not project.valid?
    assert_includes project.errors[:base_url], "is invalid"
  end

  test "accepts valid http url" do
    project = Project.new(
      platform_project_id: "plt_http",
      name: "HTTP Test",
      base_url: "http://localhost:3000"
    )
    assert project.valid?
  end

  test "accepts valid https url" do
    project = Project.new(
      platform_project_id: "plt_https",
      name: "HTTPS Test",
      base_url: "https://secure.example.com"
    )
    assert project.valid?
  end

  # ============================================
  # Associations
  # ============================================

  test "has many pages" do
    project = projects(:main_project)
    assert_respond_to project, :pages
    assert project.pages.count > 0
  end

  test "has many browser_configs" do
    project = projects(:main_project)
    assert_respond_to project, :browser_configs
    assert project.browser_configs.count > 0
  end

  test "has many test_runs" do
    project = projects(:main_project)
    assert_respond_to project, :test_runs
    assert project.test_runs.count > 0
  end

  test "has many baselines through pages" do
    project = projects(:main_project)
    assert_respond_to project, :baselines
  end

  test "has many snapshots through pages" do
    project = projects(:main_project)
    assert_respond_to project, :snapshots
  end

  test "has many ai_tasks" do
    project = projects(:main_project)
    assert_respond_to project, :ai_tasks
  end

  test "has many credentials" do
    project = projects(:main_project)
    assert_respond_to project, :credentials
  end

  test "destroys pages when project is destroyed" do
    project = projects(:main_project)
    page_ids = project.page_ids

    assert page_ids.any?

    project.destroy

    page_ids.each do |id|
      assert_nil Page.find_by(id: id)
    end
  end

  # ============================================
  # Callbacks
  # ============================================

  test "creates default browser configs after create" do
    project = Project.create!(
      platform_project_id: "plt_new_project_#{SecureRandom.hex(4)}",
      name: "New Project",
      base_url: "https://newproject.com"
    )

    assert_equal 2, project.browser_configs.count

    desktop = project.browser_configs.find_by(name: "Chrome Desktop")
    assert_not_nil desktop
    assert_equal "chromium", desktop.browser
    assert_equal 1280, desktop.width
    assert_equal 720, desktop.height
    assert_not desktop.is_mobile

    mobile = project.browser_configs.find_by(name: "Chrome Mobile")
    assert_not_nil mobile
    assert_equal "chromium", mobile.browser
    assert_equal 375, mobile.width
    assert_equal 812, mobile.height
    assert mobile.is_mobile
    assert mobile.has_touch
  end

  # ============================================
  # Settings Accessors
  # ============================================

  test "default_viewport returns settings value or default" do
    project = projects(:main_project)
    viewport = project.default_viewport

    assert_equal 1280, viewport["width"]
    assert_equal 720, viewport["height"]
  end

  test "threshold returns settings value or default" do
    project = projects(:main_project)
    assert_equal 0.01, project.threshold
  end

  test "threshold returns 0.01 as default" do
    project = Project.new(settings: {})
    assert_equal 0.01, project.threshold
  end

  test "wait_before_capture returns settings value or default" do
    project = projects(:main_project)
    assert_equal 500, project.wait_before_capture
  end

  test "hide_selectors returns empty array by default" do
    project = Project.new(settings: {})
    assert_equal [], project.hide_selectors
  end

  test "mask_selectors returns empty array by default" do
    project = Project.new(settings: {})
    assert_equal [], project.mask_selectors
  end

  # ============================================
  # AI Configuration
  # ============================================

  test "default_llm_model returns claude-sonnet-4 by default" do
    project = Project.new(settings: {})
    assert_equal "claude-sonnet-4", project.default_llm_model
  end

  test "default_browser_provider returns local by default" do
    project = Project.new(settings: {})
    assert_equal "local", project.default_browser_provider
  end

  test "ai_automation_enabled? returns true by default" do
    project = projects(:main_project)
    assert project.ai_automation_enabled?
  end

  test "ai_task_defaults returns expected defaults" do
    project = projects(:main_project)
    defaults = project.ai_task_defaults

    assert_equal 25, defaults[:max_steps]
    assert_equal 300, defaults[:timeout_seconds]
    assert_equal true, defaults[:capture_screenshots]
    assert_equal 3, defaults[:retry_count]
  end

  test "max_task_timeout returns 600 by default" do
    project = Project.new(settings: {})
    assert_equal 600, project.max_task_timeout
  end

  test "fallback_providers_enabled? returns true by default" do
    project = Project.new(settings: {})
    assert project.fallback_providers_enabled?
  end

  # ============================================
  # Class Methods
  # ============================================

  test "find_or_create_for_platform! finds existing project" do
    existing = projects(:main_project)
    found = Project.find_or_create_for_platform!(
      platform_project_id: existing.platform_project_id
    )

    assert_equal existing.id, found.id
  end

  test "find_or_create_for_platform! creates new project" do
    new_id = "plt_brand_new_#{SecureRandom.hex(4)}"

    assert_difference "Project.count", 1 do
      project = Project.find_or_create_for_platform!(
        platform_project_id: new_id,
        name: "Brand New"
      )

      assert_equal new_id, project.platform_project_id
      assert_equal "Brand New", project.name
      assert_equal "https://example.com", project.base_url
    end
  end

  # ============================================
  # Recent Summary
  # ============================================

  test "recent_summary calculates correct statistics" do
    project = projects(:main_project)
    summary = project.recent_summary

    assert_kind_of Hash, summary
    assert summary.key?(:total_runs)
    assert summary.key?(:passed)
    assert summary.key?(:failed)
    assert summary.key?(:pass_rate)
  end

  test "recent_summary pass_rate is 0 when no runs" do
    project = Project.create!(
      platform_project_id: "plt_no_runs_#{SecureRandom.hex(4)}",
      name: "No Runs Project",
      base_url: "https://example.com",
      settings: {}
    )

    summary = project.recent_summary
    assert_equal 0, summary[:pass_rate]
  end

  # ============================================
  # Vault Integration
  # ============================================

  test "vault_configured? returns false when no token" do
    project = Project.new(settings: {})
    assert_not project.vault_configured?
  end

  test "find_credential returns nil for non-existent credential" do
    project = projects(:main_project)
    assert_nil project.find_credential("non_existent")
  end

  test "credential_for_url returns nil when no matching credential" do
    project = projects(:main_project)
    assert_nil project.credential_for_url("https://unknown.com")
  end
end
