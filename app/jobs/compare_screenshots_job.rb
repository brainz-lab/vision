class CompareScreenshotsJob < ApplicationJob
  queue_as :default

  def perform(snapshot_id)
    snapshot = Snapshot.find(snapshot_id)

    # Get the baseline
    baseline = snapshot.page.current_baseline(
      snapshot.browser_config,
      branch: snapshot.test_run&.base_branch || 'main'
    )

    unless baseline
      Rails.logger.warn "No baseline found for snapshot #{snapshot_id}"

      # Auto-create baseline if this is the first snapshot
      snapshot.promote_to_baseline!
      snapshot.test_run&.increment!(:passed_count)
      check_test_run_completion(snapshot.test_run)
      return
    end

    # Run comparison
    ComparisonService.new(baseline, snapshot).compare
  rescue => e
    Rails.logger.error "CompareScreenshotsJob failed: #{e.message}"
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
