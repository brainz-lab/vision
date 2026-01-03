# frozen_string_literal: true

require "test_helper"

class CaptureScreenshotJobTest < ActiveJob::TestCase
  setup do
    @project = projects(:main_project)
    @page = pages(:homepage)
    @browser_config = browser_configs(:chrome_desktop)
    @snapshot = snapshots(:pending_snapshot)
  end

  # ============================================
  # Basic Job Execution
  # ============================================

  test "job is queued on default queue" do
    assert_equal "default", CaptureScreenshotJob.queue_name
  end

  test "job calls ScreenshotService" do
    mock_service = Minitest::Mock.new
    mock_service.expect :capture, @snapshot

    ScreenshotService.stub :new, mock_service do
      CaptureScreenshotJob.perform_now(@snapshot.id)
    end

    mock_service.verify
  end

  # ============================================
  # Test Run Integration
  # ============================================

  test "job queues comparison when baseline exists" do
    test_run = test_runs(:running_run)
    @snapshot.update!(test_run: test_run)

    # Ensure baseline exists
    baseline = baselines(:homepage_baseline)
    assert_not_nil baseline
    assert baseline.active

    # Mock ScreenshotService
    ScreenshotService.stub :new, MockScreenshotService.new(@snapshot) do
      assert_enqueued_with(job: CompareScreenshotsJob) do
        CaptureScreenshotJob.perform_now(@snapshot.id)
      end
    end
  end

  test "job promotes to baseline when no baseline exists" do
    test_run = test_runs(:running_run)

    # Use page without baseline
    page_without_baseline = pages(:disabled_page)
    page_without_baseline.update!(enabled: true)

    snapshot = Snapshot.create!(
      page: page_without_baseline,
      browser_config: @browser_config,
      test_run: test_run,
      status: "pending"
    )

    # Attach mock screenshot
    attach_screenshot(snapshot)

    ScreenshotService.stub :new, MockScreenshotService.new(snapshot) do
      assert_difference "Baseline.count", 1 do
        CaptureScreenshotJob.perform_now(snapshot.id)
      end
    end
  end

  test "job increments passed_count when promoting to baseline" do
    test_run = test_runs(:running_run)
    original_passed = test_run.passed_count

    # Use page without baseline
    page_without_baseline = pages(:disabled_page)
    page_without_baseline.update!(enabled: true)

    snapshot = Snapshot.create!(
      page: page_without_baseline,
      browser_config: @browser_config,
      test_run: test_run,
      status: "pending"
    )

    attach_screenshot(snapshot)

    ScreenshotService.stub :new, MockScreenshotService.new(snapshot) do
      CaptureScreenshotJob.perform_now(snapshot.id)
    end

    test_run.reload
    assert_equal original_passed + 1, test_run.passed_count
  end

  # ============================================
  # Error Handling
  # ============================================

  test "job marks snapshot as error on failure" do
    ScreenshotService.stub :new, ->(_) { raise StandardError.new("Network timeout") } do
      CaptureScreenshotJob.perform_now(@snapshot.id)
    end

    @snapshot.reload
    assert_equal "error", @snapshot.status
    assert @snapshot.metadata["error"].include?("Network timeout")
  end

  test "job increments test run error_count on failure" do
    test_run = test_runs(:running_run)
    @snapshot.update!(test_run: test_run)
    original_errors = test_run.error_count

    ScreenshotService.stub :new, ->(_) { raise StandardError.new("Error") } do
      CaptureScreenshotJob.perform_now(@snapshot.id)
    end

    test_run.reload
    assert_equal original_errors + 1, test_run.error_count
  end

  # ============================================
  # Test Run Completion
  # ============================================

  test "job completes test run when all pages captured" do
    test_run = TestRun.create!(
      project: @project,
      status: "running",
      started_at: 1.minute.ago,
      total_pages: 1,
      passed_count: 0,
      failed_count: 0,
      error_count: 0
    )

    # Page without baseline (will auto-promote)
    page = Page.create!(
      project: @project,
      name: "Final Page",
      path: "/final",
      slug: "final-page"
    )

    snapshot = Snapshot.create!(
      page: page,
      browser_config: @browser_config,
      test_run: test_run,
      status: "pending"
    )

    attach_screenshot(snapshot)

    ScreenshotService.stub :new, MockScreenshotService.new(snapshot) do
      CaptureScreenshotJob.perform_now(snapshot.id)
    end

    test_run.reload
    assert test_run.completed?
    assert_equal "passed", test_run.status
  end

  # ============================================
  # Helper Methods
  # ============================================

  private

  def attach_screenshot(snapshot)
    image_data = create_test_image
    snapshot.screenshot.attach(
      io: StringIO.new(image_data),
      filename: "screenshot.png",
      content_type: "image/png"
    )
    snapshot.thumbnail.attach(
      io: StringIO.new(image_data),
      filename: "thumbnail.png",
      content_type: "image/png"
    )
  end

  def create_test_image
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

  # Mock ScreenshotService that just marks snapshot as captured
  class MockScreenshotService
    def initialize(snapshot)
      @snapshot = snapshot
    end

    def capture
      @snapshot.update!(
        status: "captured",
        captured_at: Time.current,
        width: 1280,
        height: 720
      )
      @snapshot
    end
  end
end
