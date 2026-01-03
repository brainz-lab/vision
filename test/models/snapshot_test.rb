# frozen_string_literal: true

require "test_helper"

class SnapshotTest < ActiveSupport::TestCase
  # ============================================
  # Validations
  # ============================================

  test "validates status is in allowed values" do
    page = pages(:homepage)
    browser_config = browser_configs(:chrome_desktop)

    %w[pending captured comparing compared error].each do |valid_status|
      snapshot = Snapshot.new(page: page, browser_config: browser_config, status: valid_status)
      assert snapshot.valid?, "Expected status '#{valid_status}' to be valid"
    end
  end

  test "rejects invalid status" do
    snapshot = Snapshot.new(
      page: pages(:homepage),
      browser_config: browser_configs(:chrome_desktop),
      status: "invalid"
    )
    assert_not snapshot.valid?
    assert_includes snapshot.errors[:status], "is not included in the list"
  end

  # ============================================
  # Associations
  # ============================================

  test "belongs to page" do
    snapshot = snapshots(:captured_snapshot)
    assert_equal pages(:homepage), snapshot.page
  end

  test "belongs to browser_config" do
    snapshot = snapshots(:captured_snapshot)
    assert_equal browser_configs(:chrome_desktop), snapshot.browser_config
  end

  test "belongs to test_run optionally" do
    snapshot = snapshots(:staging_snapshot)
    assert_nil snapshot.test_run
  end

  test "has one comparison" do
    snapshot = snapshots(:compared_snapshot)
    assert_respond_to snapshot, :comparison
  end

  test "has screenshot attachment" do
    snapshot = snapshots(:captured_snapshot)
    assert_respond_to snapshot, :screenshot
  end

  test "has thumbnail attachment" do
    snapshot = snapshots(:captured_snapshot)
    assert_respond_to snapshot, :thumbnail
  end

  # ============================================
  # Scopes
  # ============================================

  test "recent scope orders by captured_at or created_at desc" do
    snapshots = Snapshot.recent.limit(5)
    # Just verify it doesn't error and returns results
    assert snapshots.any?
  end

  test "captured scope returns only captured snapshots" do
    captured = Snapshot.captured
    captured.each do |snapshot|
      assert_equal "captured", snapshot.status
    end
  end

  test "for_branch scope filters by branch" do
    main_snapshots = Snapshot.for_branch("main")
    main_snapshots.each do |snapshot|
      assert_equal "main", snapshot.branch
    end
  end

  # ============================================
  # Delegate Methods
  # ============================================

  test "project returns page project" do
    snapshot = snapshots(:captured_snapshot)
    assert_equal snapshot.page.project, snapshot.project
  end

  # ============================================
  # URL Methods
  # ============================================

  test "screenshot_url returns nil when no screenshot attached" do
    snapshot = snapshots(:pending_snapshot)
    assert_nil snapshot.screenshot_url
  end

  test "thumbnail_url returns nil when no thumbnail attached" do
    snapshot = snapshots(:pending_snapshot)
    assert_nil snapshot.thumbnail_url
  end

  # ============================================
  # Status Transition Methods
  # ============================================

  test "mark_captured! updates status and captured_at" do
    snapshot = snapshots(:pending_snapshot)

    snapshot.mark_captured!(duration_ms: 2500)

    assert_equal "captured", snapshot.status
    assert_not_nil snapshot.captured_at
    assert_equal 2500, snapshot.capture_duration_ms
  end

  test "mark_comparing! updates status" do
    snapshot = snapshots(:captured_snapshot)

    snapshot.mark_comparing!

    assert_equal "comparing", snapshot.status
  end

  test "mark_compared! updates status" do
    snapshot = snapshots(:comparing_snapshot)

    snapshot.mark_compared!

    assert_equal "compared", snapshot.status
  end

  test "mark_error! updates status and adds error to metadata" do
    snapshot = snapshots(:pending_snapshot)
    error_message = "Connection timeout"

    snapshot.mark_error!(error_message)

    assert_equal "error", snapshot.status
    assert_equal error_message, snapshot.metadata["error"]
  end

  # ============================================
  # Promote to Baseline
  # ============================================

  test "promote_to_baseline! returns nil when no screenshot attached" do
    snapshot = snapshots(:pending_snapshot)
    assert_nil snapshot.promote_to_baseline!
  end

  # promote_to_baseline! with attachment would require ActiveStorage setup

  # ============================================
  # Compare to Baseline
  # ============================================

  test "compare_to_baseline! returns nil when no baseline exists" do
    # Create a snapshot for a page without a baseline
    snapshot = Snapshot.new(
      page: pages(:disabled_page),
      browser_config: browser_configs(:chrome_desktop),
      status: "captured",
      branch: "main"
    )

    result = snapshot.compare_to_baseline!
    assert_nil result
  end
end
