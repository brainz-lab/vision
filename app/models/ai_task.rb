# frozen_string_literal: true

# Represents an autonomous AI browser automation task
# Tasks can be triggered via API, MCP, webhooks, or scheduled execution
class AiTask < ApplicationRecord
  belongs_to :project
  belongs_to :browser_session, optional: true
  has_many :steps, class_name: "TaskStep", dependent: :destroy
  has_many_attached :screenshots

  # Status constants
  STATUSES = %w[pending running completed stopped timeout error].freeze
  TRIGGERS = %w[api mcp webhook scheduled synapse manual].freeze

  # Validations
  validates :instruction, presence: true
  validates :model, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :triggered_by, inclusion: { in: TRIGGERS }, allow_nil: true
  validates :max_steps, numericality: { greater_than: 0, less_than_or_equal_to: 500 }
  validates :timeout_seconds, numericality: { greater_than: 0, less_than_or_equal_to: 3600 }

  # Scopes
  scope :active, -> { where(status: %w[pending running]) }
  scope :completed_tasks, -> { where(status: %w[completed stopped timeout error]) }
  scope :successful, -> { where(status: "completed") }
  scope :failed, -> { where(status: %w[stopped timeout error]) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_trigger, ->(trigger) { where(triggered_by: trigger) }

  # Callbacks
  before_validation :set_defaults, on: :create

  # Status predicates
  def pending?
    status == "pending"
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def stopped?
    status == "stopped"
  end

  def timed_out?
    status == "timeout"
  end

  def errored?
    status == "error"
  end

  def finished?
    status.in?(%w[completed stopped timeout error])
  end

  def stop_requested?
    stop_requested
  end

  def can_start?
    pending?
  end

  def can_stop?
    running?
  end

  # State transitions
  def start!
    raise "Task cannot be started" unless can_start?

    update!(
      status: "running",
      started_at: Time.current
    )
  end

  def request_stop!
    raise "Task cannot be stopped" unless can_stop?

    update!(stop_requested: true)
  end

  def complete!(result_text: nil, data: nil)
    update!(
      status: "completed",
      result: result_text,
      extracted_data: data || extracted_data,
      completed_at: Time.current,
      duration_ms: calculate_duration
    )
  end

  def stop!(reason: nil)
    update!(
      status: "stopped",
      error_message: reason || "Task stopped by user",
      completed_at: Time.current,
      duration_ms: calculate_duration
    )
  end

  def timeout!
    update!(
      status: "timeout",
      error_message: "Task exceeded #{timeout_seconds}s time limit",
      completed_at: Time.current,
      duration_ms: calculate_duration
    )
  end

  def fail!(error)
    update!(
      status: "error",
      error_message: error.is_a?(Exception) ? error.message : error.to_s,
      completed_at: Time.current,
      duration_ms: calculate_duration
    )
  end

  def increment_steps!
    increment!(:steps_executed)
  end

  # Token usage methods
  def total_tokens
    (total_input_tokens || 0) + (total_output_tokens || 0)
  end

  def recalculate_tokens!
    input = steps.sum(:input_tokens)
    output = steps.sum(:output_tokens)
    update_columns(total_input_tokens: input, total_output_tokens: output)
  end

  def add_tokens!(input:, output:)
    increment!(:total_input_tokens, input)
    increment!(:total_output_tokens, output)
  end

  # Screenshot helpers
  def screenshot_urls
    screenshots.map do |screenshot|
      Rails.application.routes.url_helpers.rails_blob_url(screenshot, only_path: true)
    end
  end

  def latest_screenshot
    screenshots.order(created_at: :desc).first
  end

  def capture_screenshots?
    capture_screenshots
  end

  # Summary for API responses
  def summary
    {
      id: id,
      instruction: instruction.truncate(100),
      status: status,
      steps_executed: steps_executed,
      model: model,
      browser_provider: browser_provider,
      triggered_by: triggered_by,
      created_at: created_at,
      duration_ms: duration_ms,
      total_tokens: total_tokens,
      total_input_tokens: total_input_tokens,
      total_output_tokens: total_output_tokens
    }
  end

  def detail
    summary.merge(
      instruction: instruction,
      start_url: start_url,
      final_url: final_url,
      result: result,
      extracted_data: extracted_data,
      error_message: error_message,
      viewport: viewport,
      max_steps: max_steps,
      started_at: started_at,
      completed_at: completed_at,
      screenshots: screenshot_urls
    )
  end

  private

  def set_defaults
    self.status ||= "pending"
    self.model ||= project&.default_llm_model || "claude-sonnet-4"
    self.browser_provider ||= project&.default_browser_provider || "local"
    self.max_steps ||= 100
    self.timeout_seconds ||= 600
    self.capture_screenshots = true if capture_screenshots.nil?
    self.viewport ||= { width: 1280, height: 720 }
    self.metadata ||= {}
    self.extracted_data ||= {}
  end

  def calculate_duration
    return nil unless started_at

    ((Time.current - started_at) * 1000).to_i
  end
end
