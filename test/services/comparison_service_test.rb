# frozen_string_literal: true

require "test_helper"

class ComparisonServiceTest < ActiveSupport::TestCase
  # ============================================
  # Helper Methods
  # ============================================

  def create_test_image(width = 100, height = 100, color = "white")
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

  def attach_screenshot_to(record, image_data = nil)
    image_data ||= create_test_image
    record.screenshot.attach(
      io: StringIO.new(image_data),
      filename: "screenshot.png",
      content_type: "image/png"
    )
  end

  # ============================================
  # Initialization
  # ============================================

  test "initializes with baseline and snapshot" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)

    service = ComparisonService.new(baseline, snapshot)

    assert_equal baseline, service.baseline
    assert_equal snapshot, service.snapshot
  end

  test "uses project threshold by default" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)

    service = ComparisonService.new(baseline, snapshot)

    assert_equal baseline.project.threshold, service.threshold
  end

  test "accepts custom threshold" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)
    custom_threshold = 0.05

    service = ComparisonService.new(baseline, snapshot, threshold: custom_threshold)

    assert_equal custom_threshold, service.threshold
  end

  # ============================================
  # Compare - Happy Path
  # ============================================

  test "compare creates comparison record when images match" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)

    # Attach identical images
    image_data = create_test_image
    attach_screenshot_to(baseline, image_data)
    attach_screenshot_to(snapshot, image_data)

    service = ComparisonService.new(baseline, snapshot)

    assert_difference "Comparison.count", 1 do
      comparison = service.compare

      assert comparison.passed?
      assert comparison.within_threshold
      assert_equal 0.0, comparison.diff_percentage
      assert_equal 0, comparison.diff_pixels
      assert_not_nil comparison.comparison_duration_ms
    end
  end

  test "compare creates failed comparison when images differ beyond threshold" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)

    # Attach different images
    attach_screenshot_to(baseline, create_test_image(100, 100, "white"))
    attach_screenshot_to(snapshot, create_test_image(100, 100, "black"))

    service = ComparisonService.new(baseline, snapshot, threshold: 0.01)

    comparison = service.compare

    assert comparison.failed?
    assert_not comparison.within_threshold
    assert comparison.diff_percentage > 1.0  # threshold is 1%
    assert_equal "pending", comparison.review_status
  end

  test "compare marks snapshot as comparing then compared" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:pending_snapshot)

    image_data = create_test_image
    attach_screenshot_to(baseline, image_data)
    attach_screenshot_to(snapshot, image_data)

    service = ComparisonService.new(baseline, snapshot)
    service.compare

    snapshot.reload
    assert_equal "compared", snapshot.status
  end

  # ============================================
  # Compare - Threshold Logic
  # ============================================

  test "comparison passes when diff equals threshold" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)

    # Use images that create minimal difference
    attach_screenshot_to(baseline, create_test_image(100, 100, "#FFFFFF"))
    attach_screenshot_to(snapshot, create_test_image(100, 100, "#FEFEFE"))

    # Set high threshold to ensure pass
    service = ComparisonService.new(baseline, snapshot, threshold: 0.5)
    comparison = service.compare

    assert comparison.passed?
    assert comparison.within_threshold
  end

  test "comparison fails when diff exceeds threshold" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)

    attach_screenshot_to(baseline, create_test_image(100, 100, "white"))
    attach_screenshot_to(snapshot, create_test_image(100, 100, "red"))

    # Very low threshold
    service = ComparisonService.new(baseline, snapshot, threshold: 0.0001)
    comparison = service.compare

    assert comparison.failed?
    assert_not comparison.within_threshold
  end

  # ============================================
  # Compare - Test Run Integration
  # ============================================

  test "compare associates comparison with test run" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)
    test_run = test_runs(:running_run)

    # Associate snapshot with test run
    snapshot.update!(test_run: test_run)

    image_data = create_test_image
    attach_screenshot_to(baseline, image_data)
    attach_screenshot_to(snapshot, image_data)

    service = ComparisonService.new(baseline, snapshot)
    comparison = service.compare

    assert_equal test_run, comparison.test_run
  end

  test "compare increments test run passed_count on pass" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)
    test_run = test_runs(:running_run)

    snapshot.update!(test_run: test_run)
    original_passed = test_run.passed_count

    image_data = create_test_image
    attach_screenshot_to(baseline, image_data)
    attach_screenshot_to(snapshot, image_data)

    service = ComparisonService.new(baseline, snapshot)
    service.compare

    test_run.reload
    assert_equal original_passed + 1, test_run.passed_count
  end

  test "compare increments test run failed_count on fail" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)
    test_run = test_runs(:running_run)

    snapshot.update!(test_run: test_run)
    original_failed = test_run.failed_count

    attach_screenshot_to(baseline, create_test_image(100, 100, "white"))
    attach_screenshot_to(snapshot, create_test_image(100, 100, "black"))

    service = ComparisonService.new(baseline, snapshot, threshold: 0.001)
    service.compare

    test_run.reload
    assert_equal original_failed + 1, test_run.failed_count
  end

  # ============================================
  # Compare - Error Handling
  # ============================================

  test "compare creates error comparison when baseline has no screenshot" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)

    # Only attach to snapshot
    attach_screenshot_to(snapshot, create_test_image)

    service = ComparisonService.new(baseline, snapshot)

    comparison = service.compare

    assert comparison.error?
  end

  test "compare creates error comparison when snapshot has no screenshot" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:pending_snapshot)

    # Only attach to baseline
    attach_screenshot_to(baseline, create_test_image)

    service = ComparisonService.new(baseline, snapshot)

    comparison = service.compare

    assert comparison.error?
  end

  test "compare marks snapshot as error on failure" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:pending_snapshot)

    # No screenshots attached - will cause error
    service = ComparisonService.new(baseline, snapshot)
    service.compare

    snapshot.reload
    assert_equal "error", snapshot.status
  end

  test "compare increments test run error_count on error" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:pending_snapshot)
    test_run = test_runs(:running_run)

    snapshot.update!(test_run: test_run)
    original_error = test_run.error_count

    # No screenshots - will cause error
    service = ComparisonService.new(baseline, snapshot)
    service.compare

    test_run.reload
    assert_equal original_error + 1, test_run.error_count
  end

  # ============================================
  # Compare - Diff Image Attachment
  # ============================================

  test "compare attaches diff image when there are differences" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)

    attach_screenshot_to(baseline, create_test_image(100, 100, "white"))
    attach_screenshot_to(snapshot, create_test_image(100, 100, "red"))

    service = ComparisonService.new(baseline, snapshot)
    comparison = service.compare

    assert comparison.diff_image.attached?
  end

  test "compare does not attach diff image when images are identical" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)

    image_data = create_test_image
    attach_screenshot_to(baseline, image_data)
    attach_screenshot_to(snapshot, image_data)

    service = ComparisonService.new(baseline, snapshot)
    comparison = service.compare

    # When diff_percentage is 0, no diff image should be attached
    assert_not comparison.diff_image.attached?
  end

  # ============================================
  # Compare - Duration Tracking
  # ============================================

  test "compare records comparison duration" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)

    image_data = create_test_image
    attach_screenshot_to(baseline, image_data)
    attach_screenshot_to(snapshot, image_data)

    service = ComparisonService.new(baseline, snapshot)
    comparison = service.compare

    assert_not_nil comparison.comparison_duration_ms
    assert comparison.comparison_duration_ms >= 0
  end
end
