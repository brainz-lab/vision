class Baseline < ApplicationRecord
  belongs_to :page, counter_cache: true
  belongs_to :browser_config

  has_many :comparisons, dependent: :destroy
  has_one_attached :screenshot
  has_one_attached :thumbnail

  validates :branch, presence: true

  scope :active, -> { where(active: true) }
  scope :for_branch, ->(branch) { where(branch: branch) }
  scope :recent, -> { order(created_at: :desc) }

  before_save :deactivate_previous, if: :active?

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

  def approve!(user_email)
    update!(
      approved_at: Time.current,
      approved_by: user_email,
      active: true
    )
  end

  private

  def deactivate_previous
    return unless active_changed? && active?

    Baseline
      .where(page: page, browser_config: browser_config, branch: branch, active: true)
      .where.not(id: id)
      .update_all(active: false)
  end
end
