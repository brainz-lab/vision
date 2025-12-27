# frozen_string_literal: true

module Api
  module V1
    # AI Task management API
    # Handles autonomous browser automation task execution
    class TasksController < BaseController
      before_action :set_task, only: %i[show stop steps]

      # GET /api/v1/tasks
      # List tasks for the project
      def index
        tasks = current_project.ai_tasks
                               .order(created_at: :desc)
                               .limit(params[:limit] || 50)

        if params[:status].present?
          tasks = tasks.where(status: params[:status])
        end

        render json: {
          tasks: tasks.map { |t| task_summary(t) },
          total: current_project.ai_tasks.count
        }
      end

      # GET /api/v1/tasks/:id
      # Get task details
      def show
        render json: {
          task: task_details(@task)
        }
      end

      # POST /api/v1/tasks
      # Create and start a new AI task
      def create
        @task = current_project.ai_tasks.build(task_params)

        if @task.save
          # Queue the task for execution
          TaskExecutorJob.perform_later(@task.id)

          render json: {
            task: task_details(@task),
            message: "Task queued for execution"
          }, status: :created
        else
          render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/tasks/:id/stop
      # Request task to stop
      def stop
        if @task.running?
          @task.update!(stop_requested: true)
          render json: {
            task: task_details(@task),
            message: "Stop requested"
          }
        elsif @task.pending?
          @task.stop!(reason: "Stopped before execution")
          render json: {
            task: task_details(@task),
            message: "Task stopped"
          }
        else
          render json: {
            error: "Task is not running",
            status: @task.status
          }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/tasks/:id/steps
      # Get task execution steps
      def steps
        steps = @task.steps.ordered

        if params[:from_position].present?
          steps = steps.where("position > ?", params[:from_position].to_i)
        end

        render json: {
          task_id: @task.id,
          steps: steps.map { |s| step_details(s) },
          total_steps: @task.steps.count
        }
      end

      private

      def set_task
        @task = current_project.ai_tasks.find(params[:id])
      end

      def task_params
        params.require(:task).permit(
          :instruction,
          :start_url,
          :model,
          :browser_provider,
          :max_steps,
          :timeout_seconds,
          :viewport,
          :capture_screenshots,
          extraction_schema: {}
        ).tap do |p|
          # Set defaults
          p[:model] ||= current_project.default_llm_model
          p[:browser_provider] ||= current_project.default_browser_provider
          p[:viewport] ||= { width: 1280, height: 720 }
        end
      end

      def task_summary(task)
        {
          id: task.id,
          instruction: task.instruction.truncate(100),
          status: task.status,
          model: task.model,
          browser_provider: task.browser_provider,
          steps_executed: task.steps_executed,
          max_steps: task.max_steps,
          created_at: task.created_at.iso8601,
          started_at: task.started_at&.iso8601,
          completed_at: task.completed_at&.iso8601,
          duration_ms: task.duration_ms
        }
      end

      def task_details(task)
        {
          id: task.id,
          instruction: task.instruction,
          start_url: task.start_url,
          final_url: task.final_url,
          status: task.status,
          model: task.model,
          browser_provider: task.browser_provider,
          max_steps: task.max_steps,
          steps_executed: task.steps_executed,
          timeout_seconds: task.timeout_seconds,
          viewport: task.viewport,
          result: task.result,
          extracted_data: task.extracted_data,
          error_message: task.error_message,
          created_at: task.created_at.iso8601,
          started_at: task.started_at&.iso8601,
          completed_at: task.completed_at&.iso8601,
          duration_ms: task.duration_ms,
          stop_requested: task.stop_requested?
        }
      end

      def step_details(step)
        {
          id: step.id,
          position: step.position,
          action: step.action,
          selector: step.selector,
          value: step.value,
          success: step.success?,
          error_message: step.error_message,
          duration_ms: step.duration_ms,
          url_before: step.url_before,
          url_after: step.url_after,
          reasoning: step.reasoning,
          executed_at: step.executed_at&.iso8601
        }
      end
    end
  end
end
