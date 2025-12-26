class Project < ApplicationRecord
  has_many :pages, dependent: :destroy
  has_many :browser_configs, dependent: :destroy
  has_many :test_runs, dependent: :destroy
  has_many :test_cases, dependent: :destroy
  has_many :baselines, through: :pages
  has_many :snapshots, through: :pages

  validates :platform_project_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :base_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }

  after_create :create_default_browser_configs

  def self.find_or_create_for_platform!(platform_project_id:, name: nil, environment: 'live')
    find_or_create_by!(platform_project_id: platform_project_id) do |p|
      p.name = name || "Project #{platform_project_id}"
      p.base_url = 'https://example.com'
      p.environment = environment
    end
  end

  def default_viewport
    settings['default_viewport'] || { 'width' => 1280, 'height' => 720 }
  end

  def threshold
    settings['threshold'] || 0.01
  end

  def wait_before_capture
    settings['wait_before_capture'] || 500
  end

  def hide_selectors
    settings['hide_selectors'] || []
  end

  def mask_selectors
    settings['mask_selectors'] || []
  end

  # Summary of recent test runs
  def recent_summary(since: 7.days.ago)
    runs = test_runs.where('created_at >= ?', since)
    {
      total_runs: runs.count,
      passed: runs.where(status: 'passed').count,
      failed: runs.where(status: 'failed').count,
      pass_rate: runs.count.positive? ? (runs.where(status: 'passed').count.to_f / runs.count * 100).round(1) : 0
    }
  end

  private

  def create_default_browser_configs
    browser_configs.create!([
      { browser: 'chromium', name: 'Chrome Desktop', width: 1280, height: 720 },
      { browser: 'chromium', name: 'Chrome Mobile', width: 375, height: 812, is_mobile: true, has_touch: true }
    ])
  end
end
