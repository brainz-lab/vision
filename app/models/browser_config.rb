class BrowserConfig < ApplicationRecord
  belongs_to :project

  has_many :baselines, dependent: :destroy
  has_many :snapshots, dependent: :destroy

  validates :browser, presence: true, inclusion: { in: %w[chromium firefox webkit] }
  validates :name, presence: true
  validates :width, presence: true, numericality: { greater_than: 0 }
  validates :height, presence: true, numericality: { greater_than: 0 }

  scope :enabled, -> { where(enabled: true) }

  # Convert to Playwright viewport config
  def to_viewport_config
    {
      width: width,
      height: height,
      device_scale_factor: device_scale_factor || 1.0,
      is_mobile: is_mobile || false,
      has_touch: has_touch || false
    }.tap do |config|
      config[:user_agent] = user_agent if user_agent.present?
    end
  end

  # Display name with resolution
  def display_name
    "#{name} (#{width}x#{height})"
  end
end
