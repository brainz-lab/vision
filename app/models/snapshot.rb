class Snapshot < ApplicationRecord
  belongs_to :page
  belongs_to :browser_config
  belongs_to :test_run, optional: true

  has_one :comparison, dependent: :destroy
  has_one_attached :screenshot
  has_one_attached :thumbnail

  validates :status, inclusion: { in: %w[pending captured comparing compared error] }

  scope :recent, -> { order(Arel.sql("COALESCE(captured_at, created_at) DESC")) }
  scope :captured, -> { where(status: 'captured') }
  scope :for_branch, ->(branch) { where(branch: branch) }

  def project
    page.project
  end

  def screenshot_url
    return nil unless screenshot.attached?
    screenshot.url
  end

  def thumbnail_url
    return nil unless thumbnail.attached?
    thumbnail.url
  end

  def mark_captured!(duration_ms: nil)
    update!(
      status: 'captured',
      captured_at: Time.current,
      capture_duration_ms: duration_ms
    )
  end

  def mark_comparing!
    update!(status: 'comparing')
  end

  def mark_compared!
    update!(status: 'compared')
  end

  def mark_error!(message = nil)
    update!(
      status: 'error',
      metadata: metadata.merge('error' => message)
    )
  end

  # Promote this snapshot to become the new baseline
  def promote_to_baseline!
    return unless screenshot.attached?

    baseline = Baseline.new(
      page: page,
      browser_config: browser_config,
      branch: branch || 'main',
      commit_sha: commit_sha,
      environment: environment,
      width: width,
      height: height,
      file_size: file_size,
      active: true,
      approved_at: Time.current
    )

    # Attach the screenshot to the new baseline
    baseline.screenshot.attach(screenshot.blob)
    baseline.thumbnail.attach(thumbnail.blob) if thumbnail.attached?

    baseline.save!
    baseline
  end

  def compare_to_baseline!
    baseline = page.current_baseline(browser_config, branch: branch_for_baseline)
    return nil unless baseline

    ComparisonService.new(baseline, self).compare
  end

  private

  def branch_for_baseline
    # PRs compare to base branch, otherwise use main
    test_run&.base_branch || 'main'
  end
end
