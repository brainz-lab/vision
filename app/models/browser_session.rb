# frozen_string_literal: true

# Represents an active browser session, either local or cloud-based
class BrowserSession < ApplicationRecord
  belongs_to :project
  has_one :ai_task

  # Status constants
  STATUSES = %w[initializing active idle error closed].freeze
  PROVIDERS = %w[local hyperbrowser browserbase stagehand director].freeze

  # Validations
  validates :provider_session_id, presence: true, uniqueness: true
  validates :browser_provider, presence: true, inclusion: { in: PROVIDERS }
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Scopes
  scope :active, -> { where(status: %w[initializing active idle]) }
  scope :closed, -> { where(status: "closed") }
  scope :expired, -> { where("expires_at < ?", Time.current) }
  scope :by_provider, ->(provider) { where(browser_provider: provider) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :set_defaults, on: :create

  # Status predicates
  def initializing?
    status == "initializing"
  end

  def active?
    status == "active"
  end

  def idle?
    status == "idle"
  end

  def errored?
    status == "error"
  end

  def closed?
    status == "closed"
  end

  def alive?
    status.in?(%w[initializing active idle])
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  # Provider predicates
  PROVIDERS.each do |provider|
    define_method("#{provider}?") do
      browser_provider == provider
    end
  end

  def cloud?
    !local?
  end

  # State transitions
  def activate!
    update!(status: "active")
  end

  def mark_idle!
    update!(status: "idle")
  end

  def mark_error!(message = nil)
    update!(
      status: "error",
      metadata: metadata.merge("error" => message)
    )
  end

  def close!
    update!(
      status: "closed",
      closed_at: Time.current
    )
  end

  # Update current state
  def update_state!(url:, title: nil)
    update!(
      current_url: url,
      current_title: title,
      status: "active"
    )
  end

  # Get the browser provider instance
  def provider
    @provider ||= BrowserProviders::Factory.for(
      browser_provider,
      credentials: project.browser_provider_config(browser_provider)
    )
  end

  # Navigation shortcuts
  def navigate(url)
    result = provider.navigate(provider_session_id, url)
    update_state!(url: result[:url], title: result[:title])
    result
  end

  def screenshot(**options)
    provider.screenshot(provider_session_id, **options)
  end

  def page_content(format: :html)
    provider.page_content(provider_session_id, format: format)
  end

  def perform_action(action:, selector: nil, value: nil, **options)
    provider.perform_action(
      provider_session_id,
      action: action,
      selector: selector,
      value: value,
      options: options
    )
  end

  # Summary for API responses
  def info
    {
      id: id,
      status: status,
      browser_provider: browser_provider,
      current_url: current_url,
      current_title: current_title,
      viewport: viewport,
      created_at: created_at,
      expires_at: expires_at
    }
  end

  # Extend session lifetime
  def extend_expiry!(duration = 30.minutes)
    update!(expires_at: duration.from_now)
  end

  private

  def set_defaults
    self.status ||= "initializing"
    self.browser_provider ||= "local"
    self.viewport ||= { width: 1280, height: 720 }
    self.metadata ||= {}
    self.expires_at ||= 30.minutes.from_now
  end
end
