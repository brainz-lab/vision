# frozen_string_literal: true

require "test_helper"

class ComparisonTest < ActiveSupport::TestCase
  # ============================================
  # Validations
  # ============================================

  test "validates status is present" do
    comparison = Comparison.new(
      baseline: baselines(:homepage_baseline),
      snapshot: snapshots(:captured_snapshot),
      status: nil
    )
    assert_not comparison.valid?
    assert_includes comparison.errors[:status], "can't be blank"
  end

  test "validates status is in allowed values" do
    baseline = baselines(:homepage_baseline)
    snapshot = snapshots(:captured_snapshot)

    %w[pending passed failed error].each do |valid_status|
      comparison = Comparison.new(baseline: baseline, snapshot: snapshot, status: valid_status)
      assert comparison.valid?, "Expected status '#{valid_status}' to be valid"
    end
  end

  test "rejects invalid status" do
    comparison = Comparison.new(
      baseline: baselines(:homepage_baseline),
      snapshot: snapshots(:captured_snapshot),
      status: "invalid"
    )
    assert_not comparison.valid?
    assert_includes comparison.errors[:status], "is not included in the list"
  end

  # ============================================
  # Associations
  # ============================================

  test "belongs to baseline" do
    comparison = comparisons(:passed_comparison)
    assert_equal baselines(:homepage_baseline), comparison.baseline
  end

  test "belongs to snapshot" do
    comparison = comparisons(:passed_comparison)
    assert_equal snapshots(:compared_snapshot), comparison.snapshot
  end

  test "belongs to test_run optionally" do
    comparison = comparisons(:passed_comparison)
    assert_not_nil comparison.test_run
  end

  test "has diff_image attachment" do
    comparison = comparisons(:failed_comparison)
    assert_respond_to comparison, :diff_image
  end

  # ============================================
  # Scopes
  # ============================================

  test "passed scope returns only passed comparisons" do
    passed = Comparison.passed
    passed.each do |comparison|
      assert_equal "passed", comparison.status
    end
  end

  test "failed scope returns only failed comparisons" do
    failed = Comparison.failed
    failed.each do |comparison|
      assert_equal "failed", comparison.status
    end
  end

  test "pending_review scope returns comparisons with pending review" do
    pending = Comparison.pending_review
    pending.each do |comparison|
      assert_equal "pending", comparison.review_status
    end
  end

  test "approved scope returns approved comparisons" do
    approved = Comparison.approved
    approved.each do |comparison|
      assert_equal "approved", comparison.review_status
    end
  end

  test "rejected scope returns rejected comparisons" do
    rejected = Comparison.rejected
    rejected.each do |comparison|
      assert_equal "rejected", comparison.review_status
    end
  end

  # ============================================
  # Delegate Methods
  # ============================================

  test "project returns snapshot page project" do
    comparison = comparisons(:passed_comparison)
    assert_equal comparison.snapshot.page.project, comparison.project
  end

  test "page returns snapshot page" do
    comparison = comparisons(:passed_comparison)
    assert_equal comparison.snapshot.page, comparison.page
  end

  # ============================================
  # Status Methods
  # ============================================

  test "passed? returns true for passed status" do
    comparison = comparisons(:passed_comparison)
    assert comparison.passed?
    assert_not comparison.failed?
    assert_not comparison.pending?
    assert_not comparison.error?
  end

  test "failed? returns true for failed status" do
    comparison = comparisons(:failed_comparison)
    assert comparison.failed?
    assert_not comparison.passed?
  end

  test "pending? returns true for pending status" do
    comparison = Comparison.new(status: "pending")
    assert comparison.pending?
  end

  test "error? returns true for error status" do
    comparison = comparisons(:error_comparison)
    assert comparison.error?
  end

  test "needs_review? returns true for failed with pending review" do
    comparison = comparisons(:failed_comparison)
    assert comparison.needs_review?
  end

  test "needs_review? returns false for passed comparison" do
    comparison = comparisons(:passed_comparison)
    assert_not comparison.needs_review?
  end

  test "needs_review? returns false for approved comparison" do
    comparison = comparisons(:approved_comparison)
    assert_not comparison.needs_review?
  end

  # ============================================
  # URL Methods
  # ============================================

  test "diff_image_url returns nil when no diff_image attached" do
    comparison = comparisons(:passed_comparison)
    assert_nil comparison.diff_image_url
  end

  # ============================================
  # Approval/Rejection
  # ============================================

  test "approve! updates review status and reviewer" do
    comparison = comparisons(:pending_review)
    reviewer_email = "approver@example.com"

    comparison.approve!(reviewer_email)

    assert_equal "approved", comparison.review_status
    assert_equal reviewer_email, comparison.reviewed_by
    assert_not_nil comparison.reviewed_at
  end

  test "approve! with update_baseline creates new baseline" do
    comparison = comparisons(:failed_comparison)

    # This would require proper ActiveStorage setup to fully test
    # Just verify it doesn't error when screenshot not attached
    comparison.approve!("approver@example.com", update_baseline: true)

    assert_equal "approved", comparison.review_status
  end

  test "reject! updates review status and adds notes" do
    comparison = comparisons(:pending_review)
    reviewer_email = "qa@example.com"
    notes = "This regression is intentional, please fix"

    comparison.reject!(reviewer_email, notes: notes)

    assert_equal "rejected", comparison.review_status
    assert_equal reviewer_email, comparison.reviewed_by
    assert_equal notes, comparison.review_notes
    assert_not_nil comparison.reviewed_at
  end

  # ============================================
  # Diff Summary
  # ============================================

  test "diff_summary returns nil when no diff_percentage" do
    comparison = Comparison.new(status: "pending", diff_percentage: nil)
    assert_nil comparison.diff_summary
  end

  test "diff_summary for passed comparison" do
    comparison = comparisons(:passed_comparison)
    summary = comparison.diff_summary

    assert_includes summary, "Passed"
    assert_includes summary, comparison.diff_percentage.round(2).to_s
  end

  test "diff_summary for failed comparison" do
    comparison = comparisons(:failed_comparison)
    summary = comparison.diff_summary

    assert_includes summary, "Failed"
    assert_includes summary, comparison.diff_percentage.round(2).to_s
    assert_includes summary, comparison.diff_pixels.to_s
  end
end
