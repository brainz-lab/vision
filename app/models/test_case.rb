class TestCase < ApplicationRecord
  belongs_to :project

  validates :name, presence: true
  validates :steps, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:position) }

  # Validate that steps are in correct format
  validate :validate_steps_format

  VALID_ACTIONS = %w[navigate click type scroll wait screenshot hover fill select].freeze

  def step_count
    steps&.length || 0
  end

  def screenshot_steps
    steps&.select { |step| step['action'] == 'screenshot' } || []
  end

  def navigation_steps
    steps&.select { |step| step['action'] == 'navigate' } || []
  end

  private

  def validate_steps_format
    return if steps.blank?

    unless steps.is_a?(Array)
      errors.add(:steps, 'must be an array')
      return
    end

    steps.each_with_index do |step, index|
      unless step.is_a?(Hash)
        errors.add(:steps, "step #{index + 1} must be an object")
        next
      end

      action = step['action']
      unless action.present? && VALID_ACTIONS.include?(action)
        errors.add(:steps, "step #{index + 1} has invalid action '#{action}'")
      end
    end
  end
end
