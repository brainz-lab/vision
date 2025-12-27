# frozen_string_literal: true

# Represents a single step/action within an AI task execution
class TaskStep < ApplicationRecord
  belongs_to :ai_task
  has_one_attached :screenshot

  # Action types
  ACTIONS = %w[click type fill navigate scroll hover select wait press extract done].freeze

  # Validations
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :action, presence: true, inclusion: { in: ACTIONS }

  # Scopes
  scope :ordered, -> { order(:position) }
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :by_action, ->(action) { where(action: action) }

  # Callbacks
  before_validation :set_position, on: :create

  # Status predicates
  def success?
    success
  end

  def failed?
    !success
  end

  # Action type predicates
  ACTIONS.each do |action_type|
    define_method("#{action_type}?") do
      action == action_type
    end
  end

  # Screenshot helpers
  def screenshot_url
    return nil unless screenshot.attached?

    Rails.application.routes.url_helpers.rails_blob_url(screenshot, only_path: true)
  end

  def attach_screenshot(data, filename: nil)
    filename ||= "task_#{ai_task_id}_step_#{position}.png"

    screenshot.attach(
      io: StringIO.new(data),
      filename: filename,
      content_type: "image/png"
    )
  end

  # Summary for display
  def action_summary
    case action
    when "click"
      "Click: #{selector || 'element'}"
    when "type"
      "Type: #{value.to_s.truncate(30)}"
    when "fill"
      "Fill #{selector || 'field'}: #{value.to_s.truncate(20)}"
    when "navigate"
      "Navigate: #{value || url_after}"
    when "scroll"
      "Scroll: #{value || 'down'}"
    when "hover"
      "Hover: #{selector || 'element'}"
    when "select"
      "Select: #{value} in #{selector || 'dropdown'}"
    when "wait"
      "Wait: #{value || '1'}s"
    when "press"
      "Press: #{value}"
    when "extract"
      "Extract data"
    when "done"
      "Task complete"
    else
      action.titleize
    end
  end

  # Token usage for this step
  def total_tokens
    (input_tokens || 0) + (output_tokens || 0)
  end

  def detail
    {
      position: position,
      action: action,
      selector: selector,
      value: value,
      action_data: action_data,
      success: success,
      error_message: error_message,
      duration_ms: duration_ms,
      url_before: url_before,
      url_after: url_after,
      reasoning: reasoning,
      screenshot_url: screenshot_url,
      executed_at: executed_at,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens
    }
  end

  private

  def set_position
    return if position.present?

    last_position = ai_task.steps.maximum(:position) || -1
    self.position = last_position + 1
  end
end
