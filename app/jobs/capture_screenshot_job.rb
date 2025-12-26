class CaptureScreenshotJob < ApplicationJob
  queue_as :default

  def perform(snapshot_id)
    snapshot = Snapshot.find(snapshot_id)

    # Capture the screenshot
    ScreenshotService.new(snapshot).capture

    # If part of a test run and there's a baseline, compare
    if snapshot.test_run && snapshot.page.current_baseline(snapshot.browser_config)
      CompareScreenshotsJob.perform_later(snapshot_id)
    elsif snapshot.test_run
      # No baseline - auto-create one
      snapshot.promote_to_baseline!
      snapshot.test_run.increment!(:passed_count)

      # Check if test run is complete
      check_test_run_completion(snapshot.test_run)
    end
  rescue => e
    Rails.logger.error "CaptureScreenshotJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    snapshot&.mark_error!(e.message)
    snapshot&.test_run&.increment!(:error_count)
    check_test_run_completion(snapshot.test_run) if snapshot&.test_run
  end

  private

  def check_test_run_completion(test_run)
    return unless test_run

    completed = test_run.passed_count + test_run.failed_count + test_run.error_count
    if completed >= test_run.total_pages
      test_run.complete!
    end
  end
end
