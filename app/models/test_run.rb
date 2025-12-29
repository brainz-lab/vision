class TestRun < ApplicationRecord
  belongs_to :project, counter_cache: true

  has_many :snapshots, dependent: :destroy
  has_many :comparisons, dependent: :destroy

  validates :status, presence: true, inclusion: { in: %w[pending running passed failed error] }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_branch, ->(branch) { where(branch: branch) }
  scope :completed, -> { where(status: %w[passed failed error]) }
  scope :in_progress, -> { where(status: %w[pending running]) }

  def pending?
    status == 'pending'
  end

  def running?
    status == 'running'
  end

  def passed?
    status == 'passed'
  end

  def failed?
    status == 'failed'
  end

  def error?
    status == 'error'
  end

  def completed?
    status.in?(%w[passed failed error])
  end

  def start!
    update!(
      status: 'running',
      started_at: Time.current
    )
  end

  def complete!
    new_status = determine_final_status

    update!(
      status: new_status,
      completed_at: Time.current,
      duration_ms: started_at ? ((Time.current - started_at) * 1000).to_i : nil
    )

    notify_results! if notification_channels.any?
  end

  def pass!
    update!(status: 'passed')
  end

  def fail!
    update!(status: 'failed')
  end

  def error!(message = nil)
    update!(status: 'error')
  end

  def summary
    {
      total: total_pages,
      passed: passed_count,
      failed: failed_count,
      pending: pending_count,
      error: error_count,
      pass_rate: total_pages.positive? ? (passed_count.to_f / total_pages * 100).round(1) : 0
    }
  end

  def progress
    return 0 if total_pages.zero?
    ((passed_count + failed_count + error_count).to_f / total_pages * 100).round(1)
  end

  def failed_comparisons
    comparisons.failed
  end

  def pending_reviews
    comparisons.pending_review
  end

  private

  def determine_final_status
    if error_count.positive?
      'error'
    elsif failed_count.positive?
      'failed'
    else
      'passed'
    end
  end

  def notify_results!
    # TODO: Implement notification sending
    update!(notified: true)
  end
end
