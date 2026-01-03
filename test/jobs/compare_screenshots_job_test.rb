# frozen_string_literal: true

require "test_helper"

class CompareScreenshotsJobTest < ActiveJob::TestCase
  setup do
    @project = projects(:main_project)
    @page = pages(:homepage)
    @browser_config = browser_configs(:chrome_desktop)
    @baseline = baselines(:homepage_baseline)
    @snapshot = snapshots(:captured_snapshot)

    # Attach images to baseline and snapshot
    attach_screenshot(@baseline)
    attach_screenshot(@snapshot)
  end

  # ============================================
  # Basic Job Execution
  # ============================================

  test "job is queued on default queue" do
    assert_equal "default", CompareScreenshotsJob.queue_name
  end

  test "job creates comparison when baseline exists" do
    assert_difference "Comparison.count", 1 do
      CompareScreenshotsJob.perform_now(@snapshot.id)
    end
  end

  test "job calls ComparisonService" do
    mock_comparison = Comparison.new(
      baseline: @baseline,
      snapshot: @snapshot,
      status: "passed",
      diff_percentage: 0.0,
      diff_pixels: 0
    )

    mock_service = Minitest::Mock.new
    mock_service.expect :compare, mock_comparison

    ComparisonService.stub :new, mock_service do
      CompareScreenshotsJob.perform_now(@snapshot.id)
    end

    mock_service.verify
  end

  # ============================================
  # No Baseline Scenarios
  # ============================================

  test "job creates baseline when none exists" do
    # Use page without baseline
    page = pages(:disabled_page)
    page.update!(enabled: true)

    snapshot = Snapshot.create!(
      page: page,
      browser_config: @browser_config,
      status: "captured"
    )
    attach_screenshot(snapshot)

    assert_difference "Baseline.count", 1 do
      CompareScreenshotsJob.perform_now(snapshot.id)
    end

    new_baseline = Baseline.where(page: page, browser_config: @browser_config).last
    assert new_baseline.active
  end

  test "job increments passed_count when creating baseline" do
    test_run = test_runs(:running_run)
    original_passed = test_run.passed_count

    page = pages(:disabled_page)
    page.update!(enabled: true)

    snapshot = Snapshot.create!(
      page: page,
      browser_config: @browser_config,
      test_run: test_run,
      status: "captured"
    )
    attach_screenshot(snapshot)

    CompareScreenshotsJob.perform_now(snapshot.id)

    test_run.reload
    assert_equal original_passed + 1, test_run.passed_count
  end

  # ============================================
  # Branch Handling
  # ============================================

  test "job uses base_branch from test run for baseline lookup" do
    test_run = test_runs(:with_pr)
    @snapshot.update!(test_run: test_run, branch: "feature/pr-123")

    # Should look for baseline on base_branch (main), not feature branch
    CompareScreenshotsJob.perform_now(@snapshot.id)

    # Should find baseline on main branch
    @snapshot.reload
    assert_equal "compared", @snapshot.status
  end

  # ============================================
  # Error Handling
  # ============================================

  test "job marks snapshot as error on failure" do
    # Force error by removing screenshot
    @baseline.screenshot.purge

    CompareScreenshotsJob.perform_now(@snapshot.id)

    @snapshot.reload
    assert_equal "error", @snapshot.status
  end

  test "job increments error_count on failure" do
    test_run = test_runs(:running_run)
    @snapshot.update!(test_run: test_run)
    original_errors = test_run.error_count

    @baseline.screenshot.purge

    CompareScreenshotsJob.perform_now(@snapshot.id)

    test_run.reload
    assert_equal original_errors + 1, test_run.error_count
  end

  # ============================================
  # Test Run Completion
  # ============================================

  test "job completes test run when all comparisons done" do
    test_run = TestRun.create!(
      project: @project,
      status: "running",
      started_at: 1.minute.ago,
      total_pages: 1,
      passed_count: 0,
      failed_count: 0,
      error_count: 0
    )

    @snapshot.update!(test_run: test_run)

    CompareScreenshotsJob.perform_now(@snapshot.id)

    test_run.reload
    assert test_run.completed?
  end

  test "job sets failed status when comparison fails" do
    test_run = TestRun.create!(
      project: @project,
      status: "running",
      started_at: 1.minute.ago,
      total_pages: 1,
      passed_count: 0,
      failed_count: 0,
      error_count: 0
    )

    @snapshot.update!(test_run: test_run)

    # Attach different images to cause failure
    attach_screenshot(@baseline, "white")
    attach_screenshot(@snapshot, "black")

    CompareScreenshotsJob.perform_now(@snapshot.id)

    test_run.reload
    assert test_run.completed?
    assert_equal "failed", test_run.status
  end

  # ============================================
  # Helper Methods
  # ============================================

  private

  def attach_screenshot(record, color = "white")
    image_data = create_test_image(color)
    record.screenshot.attach(
      io: StringIO.new(image_data),
      filename: "screenshot.png",
      content_type: "image/png"
    )
    record.thumbnail.attach(
      io: StringIO.new(image_data),
      filename: "thumbnail.png",
      content_type: "image/png"
    )
  end

  def create_test_image(color = "white")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.png")
      MiniMagick::Tool::Convert.new do |convert|
        convert.size("100x100")
        convert.xc(color)
        convert << path
      end
      File.binread(path)
    end
  end
end
