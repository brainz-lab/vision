module Dashboard
  class AiTasksController < BaseController
    before_action :set_project
    before_action :set_task, only: [:show, :retry_task]

    def index
      @tasks = @project.ai_tasks.order(created_at: :desc).limit(50)
    end

    def show
      @steps = @task.steps.order(position: :asc)
    end

    def retry_task
      # Create a new task with the same parameters
      new_task = @project.ai_tasks.create!(
        instruction: @task.instruction,
        start_url: @task.start_url,
        model: @task.model,
        browser_provider: @task.browser_provider,
        max_steps: @task.max_steps,
        timeout_seconds: @task.timeout_seconds,
        viewport: @task.viewport,
        triggered_by: "manual",
        metadata: { retried_from: @task.id }
      )

      # Execute the task in background
      executor = Ai::TaskExecutor.new(new_task)
      executor.execute!

      redirect_to dashboard_project_ai_task_path(@project, new_task),
                  notice: "Task started successfully"
    rescue => e
      redirect_to dashboard_project_ai_task_path(@project, @task),
                  alert: "Retry failed: #{e.message}"
    end

    private

    def set_task
      @task = @project.ai_tasks.find(params[:id])
    end
  end
end
