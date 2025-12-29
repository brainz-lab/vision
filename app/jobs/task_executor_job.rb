# frozen_string_literal: true

# Background job for executing AI tasks
# Uses Solid Queue with configurable timeout and progress broadcasting
class TaskExecutorJob < ApplicationJob
  queue_as :ai_tasks

  # Timeout after max_timeout + buffer for cleanup
  TIMEOUT_BUFFER_SECONDS = 30

  retry_on StandardError, wait: :polynomially_longer, attempts: 2 do |job, error|
    task = AiTask.find_by(id: job.arguments.first)
    task&.fail!(error) unless task&.finished?
  end

  discard_on ActiveRecord::RecordNotFound

  # Execute the AI task
  # @param task_id [String] UUID of the AiTask to execute
  def perform(task_id)
    task = AiTask.find(task_id)

    # Don't execute if already finished or cancelled
    return if task.finished?

    # Set up timeout
    timeout_seconds = task.timeout_seconds + TIMEOUT_BUFFER_SECONDS

    Timeout.timeout(timeout_seconds) do
      executor = Ai::TaskExecutor.new(task)

      # Set up progress callbacks
      setup_callbacks(executor, task)

      # Set up credential login if configured
      setup_credential_login(executor, task)

      # Execute the task
      executor.execute!
    end
  rescue Timeout::Error
    task = AiTask.find(task_id)
    task.timeout! unless task.finished?
  rescue => e
    Rails.logger.error "TaskExecutorJob error: #{e.message}\n#{e.backtrace.first(10).join("\n")}"

    task = AiTask.find_by(id: task_id)
    task&.fail!(e) unless task&.finished?

    raise
  end

  private

  def setup_callbacks(executor, task)
    # Broadcast step completion
    executor.on_step do |step|
      broadcast_step(task, step)
    end

    # Broadcast progress updates
    executor.on_progress do |progress|
      broadcast_progress(task, progress)
    end

    # Broadcast task completion
    executor.on_complete do |completed_task|
      broadcast_complete(completed_task)
    end
  end

  def broadcast_step(task, step)
    TaskChannel.broadcast_to(
      task,
      type: "step",
      data: {
        step_id: step.id,
        position: step.position,
        action: step.action,
        selector: step.selector,
        value: step.value,
        success: step.success?,
        error: step.error_message,
        duration_ms: step.duration_ms,
        url_after: step.url_after
      }
    )
  rescue => e
    Rails.logger.warn "Failed to broadcast step: #{e.message}"
  end

  def broadcast_progress(task, progress)
    TaskChannel.broadcast_to(
      task,
      type: "progress",
      data: {
        task_id: task.id,
        status: task.status,
        steps_executed: progress[:steps_executed],
        max_steps: task.max_steps,
        current_action: progress[:current_action],
        current_url: task.reload.final_url
      }
    )
  rescue => e
    Rails.logger.warn "Failed to broadcast progress: #{e.message}"
  end

  def broadcast_complete(task)
    TaskChannel.broadcast_to(
      task,
      type: "complete",
      data: {
        task_id: task.id,
        status: task.status,
        steps_executed: task.steps_executed,
        result: task.result,
        error: task.error_message,
        duration_ms: task.duration_ms,
        final_url: task.final_url,
        extracted_data: task.extracted_data
      }
    )
  rescue => e
    Rails.logger.warn "Failed to broadcast complete: #{e.message}"
  end

  # Set up credential login callback if task has auto_login enabled
  def setup_credential_login(executor, task)
    return unless task.metadata&.dig("auto_login")

    credential_id = task.metadata&.dig("credential_id")
    return unless credential_id

    credential = Credential.find_by(id: credential_id)
    return unless credential

    executor.before_execute do |browser, session|
      perform_credential_login(task, credential, browser, session)
    end
  end

  def perform_credential_login(task, credential, browser, session)
    session_id = session&.provider_session_id

    return unless session_id

    injector = Ai::CredentialInjector.new(
      browser: browser,
      session_id: session_id,
      project: task.project
    )

    result = injector.login(credential, navigate: true, submit: true)

    Rails.logger.info "Credential login result: #{result}"

    # Record login step in task
    task.steps.create!(
      position: 0,
      action: "credential_login",
      selector: nil,
      value: credential.name,
      action_data: { credential_name: credential.name, credential_type: credential.credential_type },
      success: result[:success],
      error_message: result[:error],
      reasoning: "Automatic login using stored credential"
    )
  rescue => e
    Rails.logger.error "Credential login failed: #{e.message}"
  end
end
