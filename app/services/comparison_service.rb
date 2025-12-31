# ComparisonService orchestrates the comparison between a baseline and a snapshot.
# It downloads images, runs the diff, and creates the comparison record.

class ComparisonService
  attr_reader :baseline, :snapshot, :threshold

  def initialize(baseline, snapshot, threshold: nil)
    @baseline = baseline
    @snapshot = snapshot
    @threshold = threshold || snapshot.page.project.threshold
  end

  def compare
    started_at = Time.current

    begin
      # Mark snapshot as comparing
      @snapshot.mark_comparing!

      # Download images
      baseline_data = download_image(@baseline)
      snapshot_data = download_image(@snapshot)

      # Perform diff
      result = DiffService.new(baseline_data, snapshot_data).diff

      # Determine status
      within_threshold = result[:diff_percentage] <= (@threshold * 100)
      status = within_threshold ? "passed" : "failed"

      # Create comparison record
      comparison = Comparison.new(
        baseline: @baseline,
        snapshot: @snapshot,
        test_run: @snapshot.test_run,
        status: status,
        diff_percentage: result[:diff_percentage],
        diff_pixels: result[:diff_pixels],
        threshold_used: @threshold,
        within_threshold: within_threshold,
        comparison_duration_ms: ((Time.current - started_at) * 1000).to_i,
        review_status: status == "failed" ? "pending" : nil
      )

      # Attach diff image if there are differences
      if result[:diff_image] && result[:diff_percentage] > 0
        comparison.diff_image.attach(
          io: StringIO.new(result[:diff_image]),
          filename: "diff_#{@snapshot.id}.png",
          content_type: "image/png"
        )
      end

      comparison.save!

      # Mark snapshot as compared
      @snapshot.mark_compared!

      # Update test run counts
      update_test_run_counts(comparison)

      comparison
    rescue => e
      Rails.logger.error "Comparison failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Create error comparison
      comparison = Comparison.create!(
        baseline: @baseline,
        snapshot: @snapshot,
        test_run: @snapshot.test_run,
        status: "error",
        comparison_duration_ms: ((Time.current - started_at) * 1000).to_i
      )

      @snapshot.mark_error!(e.message)

      # Update test run error count
      @snapshot.test_run&.increment!(:error_count)

      comparison
    end
  end

  private

  def download_image(record)
    if record.screenshot.attached?
      record.screenshot.download
    else
      raise "No screenshot attached to #{record.class.name} #{record.id}"
    end
  end

  def update_test_run_counts(comparison)
    return unless @snapshot.test_run

    case comparison.status
    when "passed"
      @snapshot.test_run.increment!(:passed_count)
    when "failed"
      @snapshot.test_run.increment!(:failed_count)
    when "error"
      @snapshot.test_run.increment!(:error_count)
    end

    # Check if all comparisons are done
    check_test_run_completion
  end

  def check_test_run_completion
    test_run = @snapshot.test_run
    return unless test_run

    completed = test_run.passed_count + test_run.failed_count + test_run.error_count
    if completed >= test_run.total_pages
      test_run.complete!
    end
  end
end
