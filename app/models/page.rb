class Page < ApplicationRecord
  belongs_to :project, counter_cache: true

  has_many :baselines, dependent: :destroy
  has_many :snapshots, dependent: :destroy
  has_one :latest_snapshot, -> { order(Arel.sql("COALESCE(captured_at, created_at) DESC")) }, class_name: "Snapshot"

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

  def staging_url
    return nil unless project.staging_url.present?
    URI.join(project.staging_url, path).to_s
  end

  def current_baseline(browser_config, branch: "main")
    baselines.where(browser_config: browser_config, branch: branch, active: true).first
  end

  def effective_viewport
    viewport || project.default_viewport
  end

  def effective_wait_ms
    wait_ms || project.wait_before_capture
  end

  def effective_hide_selectors
    hide_selectors + project.hide_selectors
  end

  def effective_mask_selectors
    mask_selectors + project.mask_selectors
  end

  def all_actions
    actions || []
  end

  private

  def generate_slug
    self.slug = name.parameterize
  end
end
