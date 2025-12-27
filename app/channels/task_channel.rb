# frozen_string_literal: true

# ActionCable channel for real-time AI task updates
# Clients can subscribe to receive step-by-step progress
class TaskChannel < ApplicationCable::Channel
  # Subscribe to a specific task's updates
  # @param task_id [String] UUID of the task to follow
  def subscribed
    task = find_task
    return reject unless task

    stream_for task
  end

  def unsubscribed
    # Cleanup when channel is unsubscribed
  end

  # Request current task state
  def request_state
    task = find_task
    return unless task

    transmit(
      type: "state",
      data: {
        task_id: task.id,
        status: task.status,
        steps_executed: task.steps_executed,
        max_steps: task.max_steps,
        current_url: task.final_url,
        started_at: task.started_at&.iso8601,
        result: task.result,
        error: task.error_message,
        recent_steps: task.steps.ordered.last(5).map do |step|
          {
            position: step.position,
            action: step.action,
            selector: step.selector,
            success: step.success?,
            executed_at: step.executed_at&.iso8601
          }
        end
      }
    )
  end

  # Request to stop the task
  def stop_task
    task = find_task
    return unless task

    if task.running?
      task.update!(stop_requested: true)
      transmit(type: "stopping", data: { task_id: task.id })
    else
      transmit(type: "error", data: { message: "Task is not running" })
    end
  end

  private

  def find_task
    task_id = params[:task_id]
    return nil unless task_id.present?

    AiTask.find_by(id: task_id)
  end
end
