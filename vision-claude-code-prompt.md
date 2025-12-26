# Vision - Visual QA & Browser Testing

## Overview

Vision is a visual regression testing and browser automation platform. It captures, compares, and validates UI changes across deployments.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│                               VISION                                         │
│                      "See what your users see"                               │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │                                                                      │   │
│   │   Before Deploy              After Deploy              Diff          │   │
│   │   ┌──────────────┐          ┌──────────────┐          ┌──────────┐  │   │
│   │   │              │          │              │          │  ██░░██  │  │   │
│   │   │   Baseline   │    vs    │   Current    │    =     │  ░░██░░  │  │   │
│   │   │  Screenshot  │          │  Screenshot  │          │  Changes │  │   │
│   │   │              │          │              │          │          │  │   │
│   │   └──────────────┘          └──────────────┘          └──────────┘  │   │
│   │                                                                      │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│   │  Screenshot │  │   Visual    │  │   Browser   │  │     E2E     │        │
│   │   Capture   │  │   Diffing   │  │ Automation  │  │   Testing   │        │
│   │             │  │             │  │             │  │             │        │
│   │ Full page,  │  │ Pixel-level │  │ Playwright  │  │ User flows  │        │
│   │ components  │  │ comparison  │  │ powered     │  │ validation  │        │
│   └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘        │
│                                                                              │
│   Features: Visual regression • Screenshot testing • Browser automation •   │
│             Component snapshots • Cross-browser • CI/CD integration        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| **API** | Rails 8 API | Test management, comparisons |
| **Browser Engine** | Playwright | Screenshot capture, automation |
| **Image Processing** | ImageMagick + pixelmatch | Visual diffing |
| **Storage** | S3/Minio | Screenshot storage |
| **Database** | PostgreSQL | Test results, baselines |
| **Queue** | Solid Queue | Async screenshot processing |
| **Real-time** | ActionCable | Live test results |

---

## Directory Structure

```
vision/
├── README.md
├── LICENSE
├── Dockerfile
├── docker-compose.yml
├── .env.example
│
├── config/
│   ├── routes.rb
│   ├── database.yml
│   └── initializers/
│       ├── playwright.rb
│       └── storage.rb
│
├── app/
│   ├── controllers/
│   │   ├── api/v1/
│   │   │   ├── projects_controller.rb
│   │   │   ├── snapshots_controller.rb
│   │   │   ├── baselines_controller.rb
│   │   │   ├── comparisons_controller.rb
│   │   │   ├── test_runs_controller.rb
│   │   │   └── browsers_controller.rb
│   │   └── webhooks/
│   │       ├── github_controller.rb
│   │       └── synapse_controller.rb
│   │
│   ├── models/
│   │   ├── project.rb
│   │   ├── page.rb
│   │   ├── snapshot.rb
│   │   ├── baseline.rb
│   │   ├── comparison.rb
│   │   ├── test_run.rb
│   │   ├── test_case.rb
│   │   └── browser_config.rb
│   │
│   ├── services/
│   │   ├── screenshot_service.rb
│   │   ├── comparison_service.rb
│   │   ├── diff_service.rb
│   │   ├── browser_pool.rb
│   │   ├── baseline_manager.rb
│   │   └── test_runner.rb
│   │
│   ├── jobs/
│   │   ├── capture_screenshot_job.rb
│   │   ├── compare_screenshots_job.rb
│   │   ├── run_test_suite_job.rb
│   │   └── cleanup_old_snapshots_job.rb
│   │
│   └── channels/
│       └── test_run_channel.rb
│
├── lib/
│   ├── vision/
│   │   ├── playwright/
│   │   │   ├── browser.rb
│   │   │   ├── page.rb
│   │   │   └── screenshot.rb
│   │   ├── diff/
│   │   │   ├── pixel_matcher.rb
│   │   │   ├── structural_matcher.rb
│   │   │   └── perceptual_matcher.rb
│   │   └── mcp/
│   │       ├── server.rb
│   │       └── tools/
│   │           ├── capture_screenshot.rb
│   │           ├── compare_screenshots.rb
│   │           ├── run_visual_test.rb
│   │           ├── get_baseline.rb
│   │           └── approve_changes.rb
│   │
│   └── tasks/
│       └── vision.rake
│
└── spec/
    ├── models/
    ├── services/
    └── requests/
```

---

## Database Schema

```ruby
# db/migrate/001_create_projects.rb

class CreateProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :projects, id: :uuid do |t|
      t.references :platform_project, type: :uuid, null: false
      
      t.string :name, null: false
      t.string :base_url, null: false          # https://myapp.com
      t.string :staging_url                     # https://staging.myapp.com
      
      # Settings
      t.jsonb :settings, default: {}
      # {
      #   default_viewport: { width: 1280, height: 720 },
      #   browsers: ["chromium", "firefox", "webkit"],
      #   threshold: 0.01,  # 1% difference allowed
      #   wait_before_capture: 500,  # ms
      #   hide_selectors: [".ads", ".timestamp"],
      #   mask_selectors: [".dynamic-content"]
      # }
      
      # Auth for protected pages
      t.jsonb :auth_config, default: {}
      # {
      #   type: "cookie" | "basic" | "bearer",
      #   credentials: { encrypted }
      # }
      
      t.timestamps
      
      t.index :platform_project_id
    end
  end
end

# db/migrate/002_create_pages.rb

class CreatePages < ActiveRecord::Migration[8.0]
  def change
    create_table :pages, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true
      
      t.string :name, null: false              # "Homepage", "Checkout"
      t.string :path, null: false              # "/", "/checkout"
      t.string :slug, null: false              # homepage, checkout
      
      # Page-specific settings (override project defaults)
      t.jsonb :viewport                        # { width: 1920, height: 1080 }
      t.jsonb :wait_for                        # { selector: ".loaded" }
      t.integer :wait_ms                       # Wait before screenshot
      
      # Actions before screenshot
      t.jsonb :actions, default: []
      # [
      #   { type: "click", selector: ".accept-cookies" },
      #   { type: "scroll", y: 500 },
      #   { type: "wait", ms: 1000 }
      # ]
      
      # Selectors to hide/mask
      t.string :hide_selectors, array: true, default: []
      t.string :mask_selectors, array: true, default: []
      
      t.boolean :enabled, default: true
      t.integer :position, default: 0
      
      t.timestamps
      
      t.index [:project_id, :slug], unique: true
      t.index [:project_id, :path]
    end
  end
end

# db/migrate/003_create_browser_configs.rb

class CreateBrowserConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :browser_configs, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true
      
      t.string :browser, null: false           # chromium, firefox, webkit
      t.string :name, null: false              # "Chrome Desktop", "Mobile Safari"
      
      t.integer :width, null: false
      t.integer :height, null: false
      t.float :device_scale_factor, default: 1.0
      t.boolean :is_mobile, default: false
      t.boolean :has_touch, default: false
      t.string :user_agent
      
      t.boolean :enabled, default: true
      
      t.timestamps
      
      t.index [:project_id, :browser]
    end
  end
end

# db/migrate/004_create_baselines.rb

class CreateBaselines < ActiveRecord::Migration[8.0]
  def change
    create_table :baselines, id: :uuid do |t|
      t.references :page, type: :uuid, null: false, foreign_key: true
      t.references :browser_config, type: :uuid, null: false, foreign_key: true
      
      # Baseline info
      t.string :branch, default: 'main'        # Git branch
      t.string :commit_sha
      t.string :environment, default: 'production'
      
      # Screenshot
      t.string :screenshot_url, null: false    # S3 URL
      t.string :thumbnail_url
      t.integer :file_size
      t.integer :width
      t.integer :height
      
      # Status
      t.boolean :active, default: true         # Current baseline
      t.datetime :approved_at
      t.string :approved_by
      
      t.timestamps
      
      t.index [:page_id, :browser_config_id, :branch, :active]
    end
  end
end

# db/migrate/005_create_snapshots.rb

class CreateSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :snapshots, id: :uuid do |t|
      t.references :page, type: :uuid, null: false, foreign_key: true
      t.references :browser_config, type: :uuid, null: false, foreign_key: true
      t.references :test_run, type: :uuid, foreign_key: true
      
      # Context
      t.string :branch
      t.string :commit_sha
      t.string :environment                    # staging, production, pr-123
      t.string :triggered_by                   # ci, manual, synapse
      
      # Screenshot
      t.string :screenshot_url, null: false
      t.string :thumbnail_url
      t.integer :file_size
      t.integer :width
      t.integer :height
      
      # Capture details
      t.datetime :captured_at
      t.integer :capture_duration_ms
      t.jsonb :metadata, default: {}           # Browser version, timing, etc.
      
      t.timestamps
      
      t.index [:page_id, :captured_at]
      t.index [:test_run_id, :page_id]
    end
  end
end

# db/migrate/006_create_comparisons.rb

class CreateComparisons < ActiveRecord::Migration[8.0]
  def change
    create_table :comparisons, id: :uuid do |t|
      t.references :baseline, type: :uuid, null: false, foreign_key: true
      t.references :snapshot, type: :uuid, null: false, foreign_key: true
      t.references :test_run, type: :uuid, foreign_key: true
      
      # Diff result
      t.string :status, null: false            # passed, failed, pending, error
      t.float :diff_percentage                 # 0.0 - 100.0
      t.integer :diff_pixels                   # Number of different pixels
      t.string :diff_image_url                 # Visual diff image
      
      # Thresholds
      t.float :threshold_used                  # 0.01 = 1%
      t.boolean :within_threshold
      
      # Review
      t.string :review_status                  # pending, approved, rejected
      t.datetime :reviewed_at
      t.string :reviewed_by
      t.text :review_notes
      
      # Performance
      t.integer :comparison_duration_ms
      
      t.timestamps
      
      t.index [:test_run_id, :status]
      t.index [:snapshot_id]
    end
  end
end

# db/migrate/007_create_test_runs.rb

class CreateTestRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :test_runs, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true
      
      # Context
      t.string :branch
      t.string :commit_sha
      t.string :commit_message
      t.string :environment
      t.string :triggered_by                   # ci, manual, synapse, webhook
      t.string :trigger_source                 # github, gitlab, api
      
      # PR info
      t.string :pr_number
      t.string :pr_url
      t.string :base_branch                    # What to compare against
      
      # Status
      t.string :status, default: 'pending'     # pending, running, passed, failed, error
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      
      # Results
      t.integer :total_pages, default: 0
      t.integer :passed_count, default: 0
      t.integer :failed_count, default: 0
      t.integer :pending_count, default: 0
      t.integer :error_count, default: 0
      
      # Notifications
      t.boolean :notified, default: false
      t.jsonb :notification_channels, default: []
      
      t.timestamps
      
      t.index [:project_id, :created_at]
      t.index [:project_id, :branch]
      t.index [:project_id, :pr_number]
    end
  end
end

# db/migrate/008_create_test_cases.rb

class CreateTestCases < ActiveRecord::Migration[8.0]
  def change
    create_table :test_cases, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true
      
      t.string :name, null: false              # "User can checkout"
      t.text :description
      
      # Test steps
      t.jsonb :steps, default: []
      # [
      #   { action: "navigate", url: "/products" },
      #   { action: "click", selector: ".add-to-cart" },
      #   { action: "screenshot", name: "cart-added" },
      #   { action: "navigate", url: "/cart" },
      #   { action: "screenshot", name: "cart-page" },
      #   { action: "click", selector: "#checkout" },
      #   { action: "screenshot", name: "checkout" }
      # ]
      
      t.string :tags, array: true, default: []
      t.boolean :enabled, default: true
      t.integer :position, default: 0
      
      t.timestamps
      
      t.index [:project_id, :enabled]
    end
  end
end
```

---

## Models

```ruby
# app/models/project.rb

class Project < ApplicationRecord
  belongs_to :platform_project, class_name: 'Platform::Project'
  
  has_many :pages, dependent: :destroy
  has_many :browser_configs, dependent: :destroy
  has_many :test_runs, dependent: :destroy
  has_many :test_cases, dependent: :destroy
  
  validates :name, presence: true
  validates :base_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp }
  
  after_create :create_default_browser_configs
  
  def default_viewport
    settings['default_viewport'] || { 'width' => 1280, 'height' => 720 }
  end
  
  def threshold
    settings['threshold'] || 0.01
  end
  
  private
  
  def create_default_browser_configs
    browser_configs.create!([
      { browser: 'chromium', name: 'Chrome Desktop', width: 1280, height: 720 },
      { browser: 'chromium', name: 'Chrome Mobile', width: 375, height: 812, is_mobile: true, has_touch: true }
    ])
  end
end

# app/models/page.rb

class Page < ApplicationRecord
  belongs_to :project
  
  has_many :baselines, dependent: :destroy
  has_many :snapshots, dependent: :destroy
  
  validates :name, presence: true
  validates :path, presence: true
  validates :slug, presence: true, uniqueness: { scope: :project_id }
  
  before_validation :generate_slug, if: -> { slug.blank? && name.present? }
  
  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:position) }
  
  def full_url(base = nil)
    base ||= project.base_url
    URI.join(base, path).to_s
  end
  
  def current_baseline(browser_config, branch: 'main')
    baselines.where(browser_config: browser_config, branch: branch, active: true).first
  end
  
  private
  
  def generate_slug
    self.slug = name.parameterize
  end
end

# app/models/snapshot.rb

class Snapshot < ApplicationRecord
  belongs_to :page
  belongs_to :browser_config
  belongs_to :test_run, optional: true
  
  has_one :comparison, dependent: :destroy
  has_one_attached :screenshot
  has_one_attached :thumbnail
  
  validates :screenshot_url, presence: true
  
  scope :recent, -> { order(captured_at: :desc) }
  
  def capture!
    ScreenshotService.new(self).capture
  end
  
  def compare_to_baseline!
    baseline = page.current_baseline(browser_config, branch: branch_for_baseline)
    return unless baseline
    
    ComparisonService.new(baseline, self).compare
  end
  
  private
  
  def branch_for_baseline
    # PRs compare to base branch, otherwise use main
    test_run&.base_branch || 'main'
  end
end

# app/models/comparison.rb

class Comparison < ApplicationRecord
  belongs_to :baseline
  belongs_to :snapshot
  belongs_to :test_run, optional: true
  
  has_one_attached :diff_image
  
  validates :status, presence: true, inclusion: { in: %w[pending passed failed error] }
  
  scope :failed, -> { where(status: 'failed') }
  scope :pending_review, -> { where(review_status: 'pending') }
  
  def passed?
    status == 'passed'
  end
  
  def failed?
    status == 'failed'
  end
  
  def approve!(user)
    update!(
      review_status: 'approved',
      reviewed_at: Time.current,
      reviewed_by: user.email
    )
    
    # Optionally update baseline
    if should_update_baseline?
      snapshot.promote_to_baseline!
    end
  end
  
  def reject!(user, notes: nil)
    update!(
      review_status: 'rejected',
      reviewed_at: Time.current,
      reviewed_by: user.email,
      review_notes: notes
    )
  end
end

# app/models/test_run.rb

class TestRun < ApplicationRecord
  belongs_to :project
  
  has_many :snapshots, dependent: :destroy
  has_many :comparisons, dependent: :destroy
  
  validates :status, presence: true
  
  scope :recent, -> { order(created_at: :desc) }
  scope :for_branch, ->(branch) { where(branch: branch) }
  
  state_machine :status, initial: :pending do
    state :pending, :running, :passed, :failed, :error
    
    event :start do
      transition pending: :running
    end
    
    event :pass do
      transition running: :passed
    end
    
    event :fail do
      transition running: :failed
    end
    
    event :error do
      transition any: :error
    end
  end
  
  def run!
    start!
    update!(started_at: Time.current)
    
    project.pages.enabled.find_each do |page|
      project.browser_configs.enabled.find_each do |browser|
        CaptureScreenshotJob.perform_later(self.id, page.id, browser.id)
      end
    end
  end
  
  def complete!
    update!(
      completed_at: Time.current,
      duration_ms: ((completed_at - started_at) * 1000).to_i
    )
    
    if failed_count.zero? && error_count.zero?
      pass!
    else
      fail!
    end
    
    notify_results!
  end
  
  def summary
    {
      total: total_pages,
      passed: passed_count,
      failed: failed_count,
      pending: pending_count,
      pass_rate: total_pages.positive? ? (passed_count.to_f / total_pages * 100).round(1) : 0
    }
  end
end
```

---

## Services

### Screenshot Service

```ruby
# app/services/screenshot_service.rb

class ScreenshotService
  def initialize(snapshot_or_page, browser_config: nil)
    if snapshot_or_page.is_a?(Snapshot)
      @snapshot = snapshot_or_page
      @page = snapshot_or_page.page
      @browser_config = snapshot_or_page.browser_config
    else
      @page = snapshot_or_page
      @browser_config = browser_config
    end
    
    @project = @page.project
  end
  
  def capture
    browser = BrowserPool.acquire(@browser_config)
    
    begin
      # Navigate to page
      browser.goto(@page.full_url)
      
      # Wait for page load
      wait_for_ready(browser)
      
      # Execute pre-capture actions
      execute_actions(browser, @page.actions)
      
      # Hide/mask elements
      apply_element_modifications(browser)
      
      # Capture screenshot
      screenshot_data = browser.screenshot(full_page: true)
      
      # Upload to storage
      url = upload_screenshot(screenshot_data)
      thumbnail_url = create_thumbnail(screenshot_data)
      
      # Update or create snapshot
      if @snapshot
        @snapshot.update!(
          screenshot_url: url,
          thumbnail_url: thumbnail_url,
          captured_at: Time.current,
          width: @browser_config.width,
          height: calculate_height(screenshot_data)
        )
      else
        Snapshot.create!(
          page: @page,
          browser_config: @browser_config,
          screenshot_url: url,
          thumbnail_url: thumbnail_url,
          captured_at: Time.current,
          width: @browser_config.width,
          height: calculate_height(screenshot_data)
        )
      end
    ensure
      BrowserPool.release(browser)
    end
  end
  
  private
  
  def wait_for_ready(browser)
    # Wait for network idle
    browser.wait_for_load_state('networkidle')
    
    # Custom wait selector
    if @page.wait_for.present?
      browser.wait_for_selector(@page.wait_for['selector'], timeout: 10_000)
    end
    
    # Additional wait time
    sleep(@page.wait_ms / 1000.0) if @page.wait_ms.present?
  end
  
  def execute_actions(browser, actions)
    actions.each do |action|
      case action['type']
      when 'click'
        browser.click(action['selector'])
      when 'scroll'
        browser.evaluate("window.scrollTo(0, #{action['y']})")
      when 'wait'
        sleep(action['ms'] / 1000.0)
      when 'type'
        browser.fill(action['selector'], action['text'])
      when 'hover'
        browser.hover(action['selector'])
      end
    end
  end
  
  def apply_element_modifications(browser)
    # Hide elements (set visibility: hidden)
    hide_selectors = @page.hide_selectors + (@project.settings['hide_selectors'] || [])
    hide_selectors.each do |selector|
      browser.evaluate("document.querySelectorAll('#{selector}').forEach(el => el.style.visibility = 'hidden')")
    end
    
    # Mask elements (replace with solid color)
    mask_selectors = @page.mask_selectors + (@project.settings['mask_selectors'] || [])
    mask_selectors.each do |selector|
      browser.evaluate(<<~JS)
        document.querySelectorAll('#{selector}').forEach(el => {
          el.style.background = '#8B5CF6';
          el.innerHTML = '';
        })
      JS
    end
  end
  
  def upload_screenshot(data)
    key = "screenshots/#{@project.id}/#{SecureRandom.uuid}.png"
    Storage.upload(key, data, content_type: 'image/png')
  end
  
  def create_thumbnail(data)
    image = MiniMagick::Image.read(data)
    image.resize('400x')
    
    key = "thumbnails/#{@project.id}/#{SecureRandom.uuid}.png"
    Storage.upload(key, image.to_blob, content_type: 'image/png')
  end
end
```

### Comparison Service

```ruby
# app/services/comparison_service.rb

class ComparisonService
  def initialize(baseline, snapshot)
    @baseline = baseline
    @snapshot = snapshot
    @threshold = snapshot.page.project.threshold
  end
  
  def compare
    started_at = Time.current
    
    begin
      # Download images
      baseline_image = download_image(@baseline.screenshot_url)
      snapshot_image = download_image(@snapshot.screenshot_url)
      
      # Perform diff
      result = DiffService.new(baseline_image, snapshot_image).diff
      
      # Determine status
      status = result[:diff_percentage] <= @threshold ? 'passed' : 'failed'
      
      # Create comparison record
      comparison = Comparison.create!(
        baseline: @baseline,
        snapshot: @snapshot,
        test_run: @snapshot.test_run,
        status: status,
        diff_percentage: result[:diff_percentage],
        diff_pixels: result[:diff_pixels],
        diff_image_url: upload_diff_image(result[:diff_image]),
        threshold_used: @threshold,
        within_threshold: result[:diff_percentage] <= @threshold,
        comparison_duration_ms: ((Time.current - started_at) * 1000).to_i,
        review_status: status == 'failed' ? 'pending' : nil
      )
      
      # Update test run counts
      update_test_run_counts(comparison)
      
      comparison
    rescue => e
      Comparison.create!(
        baseline: @baseline,
        snapshot: @snapshot,
        test_run: @snapshot.test_run,
        status: 'error',
        comparison_duration_ms: ((Time.current - started_at) * 1000).to_i
      )
    end
  end
  
  private
  
  def download_image(url)
    MiniMagick::Image.open(url)
  end
  
  def upload_diff_image(image_data)
    return nil unless image_data
    
    key = "diffs/#{@snapshot.page.project_id}/#{SecureRandom.uuid}.png"
    Storage.upload(key, image_data, content_type: 'image/png')
  end
  
  def update_test_run_counts(comparison)
    return unless @snapshot.test_run
    
    case comparison.status
    when 'passed'
      @snapshot.test_run.increment!(:passed_count)
    when 'failed'
      @snapshot.test_run.increment!(:failed_count)
    when 'error'
      @snapshot.test_run.increment!(:error_count)
    end
  end
end
```

### Diff Service

```ruby
# app/services/diff_service.rb

class DiffService
  def initialize(image1, image2, options = {})
    @image1 = image1
    @image2 = image2
    @options = options
  end
  
  def diff
    # Ensure same dimensions
    normalize_dimensions!
    
    # Use pixelmatch for accurate diffing
    result = Pixelmatch.diff(
      @image1.get_pixels,
      @image2.get_pixels,
      @image1.width,
      @image1.height,
      threshold: @options[:threshold] || 0.1,
      include_aa: @options[:include_aa] || false
    )
    
    {
      diff_pixels: result[:diff_count],
      diff_percentage: calculate_percentage(result[:diff_count]),
      diff_image: result[:diff_image],
      match_percentage: 100 - calculate_percentage(result[:diff_count])
    }
  end
  
  private
  
  def normalize_dimensions!
    # Resize to match if needed
    if @image1.dimensions != @image2.dimensions
      max_width = [@image1.width, @image2.width].max
      max_height = [@image1.height, @image2.height].max
      
      @image1.resize("#{max_width}x#{max_height}!")
      @image2.resize("#{max_width}x#{max_height}!")
    end
  end
  
  def calculate_percentage(diff_pixels)
    total_pixels = @image1.width * @image1.height
    (diff_pixels.to_f / total_pixels * 100).round(4)
  end
end
```

### Browser Pool

```ruby
# app/services/browser_pool.rb

class BrowserPool
  POOL_SIZE = 5
  
  class << self
    def acquire(browser_config)
      pool = pool_for(browser_config)
      pool.checkout
    end
    
    def release(browser)
      browser.context.close
    end
    
    private
    
    def pool_for(browser_config)
      @pools ||= {}
      @pools[browser_config.id] ||= create_pool(browser_config)
    end
    
    def create_pool(browser_config)
      ConnectionPool.new(size: POOL_SIZE, timeout: 30) do
        playwright = Playwright.create(playwright_cli_executable_path: 'npx playwright')
        browser = playwright.send(browser_config.browser.to_sym).launch(headless: true)
        
        context = browser.new_context(
          viewport: { width: browser_config.width, height: browser_config.height },
          device_scale_factor: browser_config.device_scale_factor,
          is_mobile: browser_config.is_mobile,
          has_touch: browser_config.has_touch,
          user_agent: browser_config.user_agent
        )
        
        context.new_page
      end
    end
  end
end
```

---

## Controllers

```ruby
# app/controllers/api/v1/snapshots_controller.rb

module Api
  module V1
    class SnapshotsController < BaseController
      before_action :set_page
      
      # POST /api/v1/pages/:page_id/snapshots
      def create
        browser_config = @page.project.browser_configs.find(params[:browser_config_id])
        
        snapshot = @page.snapshots.create!(
          browser_config: browser_config,
          branch: params[:branch],
          commit_sha: params[:commit_sha],
          environment: params[:environment],
          triggered_by: 'api'
        )
        
        CaptureScreenshotJob.perform_later(snapshot.id)
        
        render json: SnapshotSerializer.new(snapshot).serializable_hash, status: :created
      end
      
      # GET /api/v1/pages/:page_id/snapshots
      def index
        snapshots = @page.snapshots.recent.limit(50)
        render json: SnapshotSerializer.new(snapshots).serializable_hash
      end
      
      private
      
      def set_page
        @page = current_project.pages.find(params[:page_id])
      end
    end
  end
end

# app/controllers/api/v1/test_runs_controller.rb

module Api
  module V1
    class TestRunsController < BaseController
      # POST /api/v1/test_runs
      def create
        test_run = current_project.test_runs.create!(
          branch: params[:branch],
          commit_sha: params[:commit_sha],
          commit_message: params[:commit_message],
          environment: params[:environment] || 'staging',
          pr_number: params[:pr_number],
          pr_url: params[:pr_url],
          base_branch: params[:base_branch] || 'main',
          triggered_by: params[:triggered_by] || 'api',
          trigger_source: params[:trigger_source]
        )
        
        RunTestSuiteJob.perform_later(test_run.id)
        
        render json: TestRunSerializer.new(test_run).serializable_hash, status: :created
      end
      
      # GET /api/v1/test_runs/:id
      def show
        test_run = current_project.test_runs.find(params[:id])
        render json: TestRunSerializer.new(test_run, include: [:comparisons]).serializable_hash
      end
      
      # GET /api/v1/test_runs
      def index
        test_runs = current_project.test_runs.recent.limit(50)
        
        if params[:branch]
          test_runs = test_runs.for_branch(params[:branch])
        end
        
        render json: TestRunSerializer.new(test_runs).serializable_hash
      end
    end
  end
end

# app/controllers/api/v1/comparisons_controller.rb

module Api
  module V1
    class ComparisonsController < BaseController
      # POST /api/v1/comparisons/:id/approve
      def approve
        comparison = find_comparison
        comparison.approve!(current_user)
        
        render json: ComparisonSerializer.new(comparison).serializable_hash
      end
      
      # POST /api/v1/comparisons/:id/reject
      def reject
        comparison = find_comparison
        comparison.reject!(current_user, notes: params[:notes])
        
        render json: ComparisonSerializer.new(comparison).serializable_hash
      end
      
      # POST /api/v1/comparisons/:id/update_baseline
      def update_baseline
        comparison = find_comparison
        
        # Promote snapshot to new baseline
        comparison.snapshot.promote_to_baseline!
        comparison.approve!(current_user)
        
        render json: { message: 'Baseline updated' }
      end
      
      private
      
      def find_comparison
        Comparison.joins(snapshot: { page: :project })
                  .where(pages: { project_id: current_project.id })
                  .find(params[:id])
      end
    end
  end
end
```

---

## MCP Tools

```ruby
# lib/vision/mcp/tools/capture_screenshot.rb

module Vision
  module Mcp
    module Tools
      class CaptureScreenshot < BaseTool
        TOOL_NAME = 'vision_capture'
        DESCRIPTION = 'Capture a screenshot of a page'
        
        SCHEMA = {
          type: 'object',
          properties: {
            url: {
              type: 'string',
              description: 'URL to capture'
            },
            page_name: {
              type: 'string',
              description: 'Name for the page (for organizing)'
            },
            viewport: {
              type: 'object',
              properties: {
                width: { type: 'integer' },
                height: { type: 'integer' }
              }
            },
            full_page: {
              type: 'boolean',
              default: true
            }
          },
          required: ['url']
        }.freeze
        
        def call(args)
          page = find_or_create_page(args)
          browser_config = project.browser_configs.first
          
          snapshot = page.snapshots.create!(
            browser_config: browser_config,
            triggered_by: 'mcp'
          )
          
          ScreenshotService.new(snapshot).capture
          
          {
            snapshot_id: snapshot.id,
            url: snapshot.screenshot_url,
            page: page.name
          }
        end
      end
      
      class CompareScreenshots < BaseTool
        TOOL_NAME = 'vision_compare'
        DESCRIPTION = 'Compare current page to baseline'
        
        SCHEMA = {
          type: 'object',
          properties: {
            page: {
              type: 'string',
              description: 'Page name or path'
            },
            threshold: {
              type: 'number',
              description: 'Diff threshold (0.01 = 1%)',
              default: 0.01
            }
          },
          required: ['page']
        }.freeze
        
        def call(args)
          page = find_page(args[:page])
          browser_config = project.browser_configs.first
          
          # Capture current state
          snapshot = page.snapshots.create!(
            browser_config: browser_config,
            triggered_by: 'mcp'
          )
          ScreenshotService.new(snapshot).capture
          
          # Compare to baseline
          comparison = snapshot.compare_to_baseline!
          
          {
            status: comparison.status,
            diff_percentage: comparison.diff_percentage,
            passed: comparison.passed?,
            diff_url: comparison.diff_image_url,
            message: comparison.passed? ? 
              'Visual test passed' : 
              "Visual difference detected: #{comparison.diff_percentage}%"
          }
        end
      end
      
      class RunVisualTest < BaseTool
        TOOL_NAME = 'vision_test'
        DESCRIPTION = 'Run visual regression test for all pages'
        
        SCHEMA = {
          type: 'object',
          properties: {
            branch: {
              type: 'string',
              description: 'Git branch'
            },
            pages: {
              type: 'array',
              items: { type: 'string' },
              description: 'Specific pages to test (optional)'
            }
          }
        }.freeze
        
        def call(args)
          test_run = project.test_runs.create!(
            branch: args[:branch],
            triggered_by: 'mcp'
          )
          
          test_run.run!
          
          # Wait for completion (with timeout)
          wait_for_completion(test_run)
          
          {
            test_run_id: test_run.id,
            status: test_run.status,
            summary: test_run.summary,
            failed_pages: test_run.comparisons.failed.map { |c| c.snapshot.page.name }
          }
        end
        
        private
        
        def wait_for_completion(test_run, timeout: 120)
          start = Time.current
          loop do
            test_run.reload
            break if test_run.status.in?(%w[passed failed error])
            break if Time.current - start > timeout
            sleep 2
          end
        end
      end
      
      class ApproveChanges < BaseTool
        TOOL_NAME = 'vision_approve'
        DESCRIPTION = 'Approve visual changes and update baseline'
        
        SCHEMA = {
          type: 'object',
          properties: {
            comparison_id: {
              type: 'string',
              description: 'Comparison ID to approve'
            },
            update_baseline: {
              type: 'boolean',
              default: true,
              description: 'Update baseline with new screenshot'
            }
          },
          required: ['comparison_id']
        }.freeze
        
        def call(args)
          comparison = Comparison.find(args[:comparison_id])
          
          if args[:update_baseline]
            comparison.snapshot.promote_to_baseline!
          end
          
          comparison.approve!(current_user)
          
          {
            approved: true,
            baseline_updated: args[:update_baseline],
            message: "Changes approved for #{comparison.snapshot.page.name}"
          }
        end
      end
    end
  end
end
```

---

## Synapse Integration

```ruby
# Integration with Synapse Tester Agent

module Agents
  class TesterAgent < BaseAgent
    TOOLS = [
      # Vision - Visual Testing (NEW!)
      'vision_capture',         # Capture screenshot
      'vision_compare',         # Compare to baseline
      'vision_test',            # Run full visual test
      'vision_approve',         # Approve changes
      'vision_list_failures',   # List failed comparisons
      
      # Browser Actions (existing)
      'browser_navigate',
      'browser_click',
      'browser_type',
      # ...
    ].freeze
    
    # When running visual tests
    def run_visual_tests
      result = tool_call('vision_test', { 
        branch: @task.branch 
      })
      
      if result[:status] == 'failed'
        notify_failures(result[:failed_pages])
      end
      
      result
    end
  end
end
```

---

## CI/CD Integration

### GitHub Action

```yaml
# .github/workflows/visual-test.yml

name: Visual Regression Tests

on:
  pull_request:
    branches: [main, develop]

jobs:
  visual-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run Visual Tests
        uses: brainzlab/vision-action@v1
        with:
          api-key: ${{ secrets.BRAINZLAB_API_KEY }}
          base-url: ${{ secrets.STAGING_URL }}
          branch: ${{ github.head_ref }}
          pr-number: ${{ github.event.pull_request.number }}
      
      - name: Comment PR with Results
        if: always()
        uses: brainzlab/vision-comment@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

---

## Routes

```ruby
# config/routes.rb

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :projects do
        resources :pages do
          resources :snapshots, only: [:index, :create, :show]
          resources :baselines, only: [:index, :show, :update]
        end
        
        resources :browser_configs
        resources :test_runs, only: [:index, :create, :show]
        resources :test_cases
      end
      
      resources :comparisons, only: [:show] do
        member do
          post :approve
          post :reject
          post :update_baseline
        end
      end
    end
  end
  
  # Webhooks
  namespace :webhooks do
    post 'github', to: 'github#create'
    post 'synapse', to: 'synapse#create'
  end
  
  # Health
  get 'health', to: 'health#show'
end
```

---

## Docker Compose

```yaml
# docker-compose.yml

version: '3.8'

services:
  web:
    build: .
    ports:
      - "3007:3000"
    environment:
      - DATABASE_URL=postgres://postgres:postgres@db:5432/vision
      - REDIS_URL=redis://redis:6379
      - STORAGE_BUCKET=vision-screenshots
      - MINIO_ENDPOINT=http://minio:9000
    depends_on:
      - db
      - redis
      - minio
      - playwright
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.vision.rule=Host(`vision.brainzlab.localhost`)"

  worker:
    build: .
    command: bundle exec rake solid_queue:start
    environment:
      - DATABASE_URL=postgres://postgres:postgres@db:5432/vision
      - REDIS_URL=redis://redis:6379
      - STORAGE_BUCKET=vision-screenshots
    depends_on:
      - db
      - redis
      - playwright

  playwright:
    image: mcr.microsoft.com/playwright:v1.40.0-focal
    environment:
      - PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
    shm_size: 2gb

  db:
    image: postgres:16-alpine
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=vision
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    volumes:
      - redis_data:/data

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    environment:
      - MINIO_ROOT_USER=minioadmin
      - MINIO_ROOT_PASSWORD=minioadmin
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio_data:/data

volumes:
  postgres_data:
  redis_data:
  minio_data:
```

---

## Summary

### Vision Features

| Feature | Description |
|---------|-------------|
| **Screenshot Capture** | Full page & component screenshots |
| **Visual Diffing** | Pixel-level comparison with threshold |
| **Baseline Management** | Track approved states per branch |
| **Cross-browser** | Chromium, Firefox, WebKit |
| **Responsive Testing** | Desktop, tablet, mobile viewports |
| **CI/CD Integration** | GitHub Actions, webhooks |
| **MCP Tools** | AI assistant integration |

### MCP Tools

| Tool | Description |
|------|-------------|
| `vision_capture` | Capture screenshot of URL |
| `vision_compare` | Compare to baseline |
| `vision_test` | Run full visual test suite |
| `vision_approve` | Approve changes, update baseline |

### Integration Points

| Product | Integration |
|---------|-------------|
| **Synapse** | Tester Agent uses Vision for visual tests |
| **Signal** | Alert on visual regression failures |
| **Cortex** | Feature flag testing with screenshots |

---

*Vision = Eyes on every deploy! 👁️*
