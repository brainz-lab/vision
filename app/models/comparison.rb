class Comparison < ApplicationRecord
  belongs_to :baseline
  belongs_to :snapshot
  belongs_to :test_run, optional: true

  has_one_attached :diff_image

  validates :status, presence: true, inclusion: { in: %w[pending passed failed error] }

  scope :passed, -> { where(status: "passed") }
  scope :failed, -> { where(status: "failed") }
  scope :pending_review, -> { where(review_status: "pending") }
  scope :approved, -> { where(review_status: "approved") }
  scope :rejected, -> { where(review_status: "rejected") }

  def project
    snapshot.page.project
  end

  def page
    snapshot.page
  end

  def passed?
    status == "passed"
  end

  def failed?
    status == "failed"
  end

  def pending?
    status == "pending"
  end

  def error?
    status == "error"
  end

  def needs_review?
    review_status == "pending" && failed?
  end

  def diff_image_url
    return nil unless diff_image.attached?
    diff_image.url
  end

  def approve!(user_email, update_baseline: false)
    transaction do
      update!(
        review_status: "approved",
        reviewed_at: Time.current,
        reviewed_by: user_email
      )

      # Optionally update baseline
      if update_baseline
        snapshot.promote_to_baseline!
      end

      # Update test run counts
      if test_run && failed?
        test_run.decrement!(:failed_count)
        test_run.increment!(:passed_count)
      end
    end
  end

  def reject!(user_email, notes: nil)
    update!(
      review_status: "rejected",
      reviewed_at: Time.current,
      reviewed_by: user_email,
      review_notes: notes
    )
  end

  def diff_summary
    return nil unless diff_percentage

    if passed?
      "Passed (#{diff_percentage.round(2)}% difference)"
    else
      "Failed (#{diff_percentage.round(2)}% difference, #{diff_pixels} pixels changed)"
    end
  end
end
