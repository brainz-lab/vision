# frozen_string_literal: true

require "test_helper"

class BaselineTest < ActiveSupport::TestCase
  # ============================================
  # Validations
  # ============================================

  test "validates presence of branch" do
    baseline = Baseline.new(
      page: pages(:homepage),
      browser_config: browser_configs(:chrome_desktop),
      branch: nil
    )
    # Branch has a default value in the schema, so explicitly set to blank
    baseline.branch = ""
    assert_not baseline.valid?
    assert_includes baseline.errors[:branch], "can't be blank"
  end

  test "valid baseline with all required attributes" do
    baseline = Baseline.new(
      page: pages(:homepage),
      browser_config: browser_configs(:chrome_desktop),
      branch: "feature/test"
    )
    assert baseline.valid?
  end

  # ============================================
  # Associations
  # ============================================

  test "belongs to page with counter_cache" do
    baseline = baselines(:homepage_baseline)
    assert_equal pages(:homepage), baseline.page
  end

  test "belongs to browser_config" do
    baseline = baselines(:homepage_baseline)
    assert_equal browser_configs(:chrome_desktop), baseline.browser_config
  end

  test "has many comparisons" do
    baseline = baselines(:homepage_baseline)
    assert_respond_to baseline, :comparisons
  end

  test "has screenshot attachment" do
    baseline = baselines(:homepage_baseline)
    assert_respond_to baseline, :screenshot
  end

  test "has thumbnail attachment" do
    baseline = baselines(:homepage_baseline)
    assert_respond_to baseline, :thumbnail
  end

  # ============================================
  # Scopes
  # ============================================

  test "active scope returns only active baselines" do
    active = Baseline.active
    active.each do |baseline|
      assert baseline.active
    end
  end

  test "for_branch scope filters by branch" do
    main_baselines = Baseline.for_branch("main")
    main_baselines.each do |baseline|
      assert_equal "main", baseline.branch
    end
  end

  test "recent scope orders by created_at desc" do
    baselines = Baseline.recent.limit(5)
    assert baselines.first.created_at >= baselines.last.created_at
  end

  # ============================================
  # Delegate Methods
  # ============================================

  test "project returns page project" do
    baseline = baselines(:homepage_baseline)
    assert_equal baseline.page.project, baseline.project
  end

  # ============================================
  # URL Methods
  # ============================================

  test "screenshot_url returns nil when no screenshot attached" do
    baseline = Baseline.new(
      page: pages(:homepage),
      browser_config: browser_configs(:chrome_desktop),
      branch: "test"
    )
    assert_nil baseline.screenshot_url
  end

  test "thumbnail_url returns nil when no thumbnail attached" do
    baseline = Baseline.new(
      page: pages(:homepage),
      browser_config: browser_configs(:chrome_desktop),
      branch: "test"
    )
    assert_nil baseline.thumbnail_url
  end

  # ============================================
  # Approval
  # ============================================

  test "approve! sets approved_at, approved_by, and active" do
    baseline = Baseline.create!(
      page: pages(:login_page),
      browser_config: browser_configs(:chrome_mobile),
      branch: "new-feature",
      active: false
    )
    approver = "approver@example.com"

    baseline.approve!(approver)

    assert baseline.active
    assert_not_nil baseline.approved_at
    assert_equal approver, baseline.approved_by
  end

  # ============================================
  # Deactivate Previous Baseline
  # ============================================

  test "deactivates previous baseline when new one becomes active" do
    page = pages(:login_page)
    browser_config = browser_configs(:firefox_desktop)

    # Create first baseline (inactive initially)
    first = Baseline.create!(
      page: page,
      browser_config: browser_config,
      branch: "main",
      active: false
    )

    # Make it active via update
    first.update!(active: true)
    assert first.active

    # Create second baseline inactive, then make it active
    second = Baseline.create!(
      page: page,
      browser_config: browser_config,
      branch: "main",
      active: false
    )

    # Make second active - this should deactivate first
    second.update!(active: true)

    # Reload first baseline
    first.reload

    assert_not first.active
    assert second.active
  end

  test "does not deactivate baselines from different branches" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)

    # Existing baseline is for main branch
    main_baseline = baselines(:homepage_baseline)
    assert main_baseline.active

    # Create baseline for different branch
    feature_baseline = Baseline.create!(
      page: page,
      browser_config: browser_config,
      branch: "feature/new",
      active: true
    )

    # Main baseline should still be active
    main_baseline.reload
    assert main_baseline.active
    assert feature_baseline.active
  end

  test "does not deactivate baselines from different browser configs" do
    page = pages(:homepage)

    # Existing desktop baseline
    desktop_baseline = baselines(:homepage_baseline)
    assert desktop_baseline.active

    # Create baseline for mobile
    mobile_baseline = baselines(:homepage_mobile_baseline)
    assert mobile_baseline.active

    # Both should be active (different browser configs)
    desktop_baseline.reload
    assert desktop_baseline.active
  end
end
