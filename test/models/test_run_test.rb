# frozen_string_literal: true

require "test_helper"

class TestRunTest < ActiveSupport::TestCase
  # ============================================
  # Validations
  # ============================================

  test "validates status is present" do
    test_run = TestRun.new(project: projects(:main_project), status: nil)
    assert_not test_run.valid?
    assert_includes test_run.errors[:status], "can't be blank"
  end

  test "validates status is in allowed values" do
    project = projects(:main_project)

    %w[pending running passed failed error].each do |valid_status|
      test_run = TestRun.new(project: project, status: valid_status)
      assert test_run.valid?, "Expected status '#{valid_status}' to be valid"
    end
  end

  test "rejects invalid status" do
    test_run = TestRun.new(project: projects(:main_project), status: "invalid")
    assert_not test_run.valid?
    assert_includes test_run.errors[:status], "is not included in the list"
  end

  # ============================================
  # Associations
  # ============================================

  test "belongs to project" do
    test_run = test_runs(:pending_run)
    assert_respond_to test_run, :project
    assert_equal projects(:main_project), test_run.project
  end

  test "has many snapshots" do
    test_run = test_runs(:passed_run)
    assert_respond_to test_run, :snapshots
  end

  test "has many comparisons" do
    test_run = test_runs(:passed_run)
    assert_respond_to test_run, :comparisons
  end

  # ============================================
  # Scopes
  # ============================================

  test "recent scope orders by created_at desc" do
    runs = TestRun.recent.limit(5)
    assert runs.first.created_at >= runs.last.created_at
  end

  test "for_branch scope filters by branch" do
    runs = TestRun.for_branch("main")
    runs.each do |run|
      assert_equal "main", run.branch
    end
  end

  test "completed scope includes passed, failed, error" do
    completed = TestRun.completed
    completed.each do |run|
      assert_includes %w[passed failed error], run.status
    end
  end

  test "in_progress scope includes pending and running" do
    in_progress = TestRun.in_progress
    in_progress.each do |run|
      assert_includes %w[pending running], run.status
    end
  end

  # ============================================
  # Status Methods
  # ============================================

  test "pending? returns true for pending status" do
    test_run = test_runs(:pending_run)
    assert test_run.pending?
    assert_not test_run.running?
    assert_not test_run.passed?
    assert_not test_run.failed?
    assert_not test_run.error?
  end

  test "running? returns true for running status" do
    test_run = test_runs(:running_run)
    assert test_run.running?
    assert_not test_run.pending?
    assert_not test_run.completed?
  end

  test "passed? returns true for passed status" do
    test_run = test_runs(:passed_run)
    assert test_run.passed?
    assert test_run.completed?
  end

  test "failed? returns true for failed status" do
    test_run = test_runs(:failed_run)
    assert test_run.failed?
    assert test_run.completed?
  end

  test "error? returns true for error status" do
    test_run = test_runs(:error_run)
    assert test_run.error?
    assert test_run.completed?
  end

  test "completed? returns true for terminal states" do
    assert test_runs(:passed_run).completed?
    assert test_runs(:failed_run).completed?
    assert test_runs(:error_run).completed?
    assert_not test_runs(:pending_run).completed?
    assert_not test_runs(:running_run).completed?
  end

  # ============================================
  # Lifecycle Methods
  # ============================================

  test "start! sets status to running and started_at" do
    test_run = test_runs(:pending_run)
    assert_nil test_run.started_at

    test_run.start!

    assert test_run.running?
    assert_not_nil test_run.started_at
    assert_in_delta Time.current, test_run.started_at, 1.second
  end

  test "complete! sets passed status when no failures or errors" do
    test_run = TestRun.create!(
      project: projects(:main_project),
      status: "running",
      started_at: 1.minute.ago,
      total_pages: 3,
      passed_count: 3,
      failed_count: 0,
      error_count: 0
    )

    test_run.complete!

    assert test_run.passed?
    assert_not_nil test_run.completed_at
    assert_not_nil test_run.duration_ms
  end

  test "complete! sets failed status when there are failures" do
    test_run = TestRun.create!(
      project: projects(:main_project),
      status: "running",
      started_at: 1.minute.ago,
      total_pages: 3,
      passed_count: 2,
      failed_count: 1,
      error_count: 0
    )

    test_run.complete!

    assert test_run.failed?
  end

  test "complete! sets error status when there are errors" do
    test_run = TestRun.create!(
      project: projects(:main_project),
      status: "running",
      started_at: 1.minute.ago,
      total_pages: 3,
      passed_count: 2,
      failed_count: 0,
      error_count: 1
    )

    test_run.complete!

    assert test_run.error?
  end

  test "pass! sets status to passed" do
    test_run = test_runs(:running_run)
    test_run.pass!
    assert test_run.passed?
  end

  test "fail! sets status to failed" do
    test_run = test_runs(:running_run)
    test_run.fail!
    assert test_run.failed?
  end

  test "error! sets status to error" do
    test_run = test_runs(:running_run)
    test_run.error!
    assert test_run.error?
  end

  # ============================================
  # Summary and Progress
  # ============================================

  test "summary returns correct statistics" do
    test_run = test_runs(:failed_run)
    summary = test_run.summary

    assert_equal 4, summary[:total]
    assert_equal 2, summary[:passed]
    assert_equal 2, summary[:failed]
    assert_equal 0, summary[:error]
    assert_equal 50.0, summary[:pass_rate]
  end

  test "summary pass_rate is 0 when no total pages" do
    test_run = TestRun.new(total_pages: 0)
    assert_equal 0, test_run.summary[:pass_rate]
  end

  test "progress returns correct percentage" do
    test_run = test_runs(:running_run)
    # total_pages: 3, passed: 1, failed: 0, error: 0
    # progress = (1 + 0 + 0) / 3 * 100 = 33.3
    expected = ((1 + 0 + 0).to_f / 3 * 100).round(1)
    assert_equal expected, test_run.progress
  end

  test "progress returns 0 when total_pages is zero" do
    test_run = TestRun.new(total_pages: 0)
    assert_equal 0, test_run.progress
  end

  test "progress returns 100 for completed run" do
    test_run = test_runs(:passed_run)
    # passed_count: 3, failed_count: 0, error_count: 0, total_pages: 3
    assert_equal 100.0, test_run.progress
  end

  # ============================================
  # Comparison Queries
  # ============================================

  test "failed_comparisons returns failed comparisons" do
    test_run = test_runs(:failed_run)
    failed = test_run.failed_comparisons

    failed.each do |comparison|
      assert comparison.failed?
    end
  end

  test "pending_reviews returns pending review comparisons" do
    test_run = test_runs(:failed_run)
    pending = test_run.pending_reviews

    pending.each do |comparison|
      assert_equal "pending", comparison.review_status
    end
  end
end
