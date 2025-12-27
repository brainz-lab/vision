# frozen_string_literal: true

module Mcp
  module Tools
    # Execute an autonomous multi-step AI browser task
    class VisionTask < Base
      DESCRIPTION = "Execute an autonomous browser task with AI. The AI agent will navigate, click, type, and extract data to complete your instruction."

      SCHEMA = {
        type: "object",
        properties: {
          instruction: {
            type: "string",
            description: "Natural language task instruction (e.g., 'Go to amazon.com, search for laptop, get top 5 prices')"
          },
          start_url: {
            type: "string",
            description: "Starting URL for the task"
          },
          model: {
            type: "string",
            enum: %w[claude-sonnet-4 claude-opus-4 gpt-4o gpt-4o-mini gemini-2.5-flash gemini-2.0-flash],
            default: "claude-sonnet-4",
            description: "LLM model to use for decision making"
          },
          browser_provider: {
            type: "string",
            enum: %w[local hyperbrowser browserbase stagehand director],
            default: "local",
            description: "Browser provider to use"
          },
          max_steps: {
            type: "integer",
            default: 30,
            minimum: 1,
            maximum: 100,
            description: "Maximum number of steps before stopping"
          },
          timeout_seconds: {
            type: "integer",
            default: 300,
            minimum: 30,
            maximum: 600,
            description: "Maximum time in seconds for the task"
          },
          extraction_schema: {
            type: "object",
            description: "Optional JSON schema for structured data extraction"
          },
          wait_for_completion: {
            type: "boolean",
            default: true,
            description: "Wait for task completion (sync) or return immediately (async)"
          }
        },
        required: %w[instruction]
      }.freeze

      def call(args)
        instruction = args[:instruction]
        start_url = args[:start_url]
        wait = args.fetch(:wait_for_completion, true)

        # Create the task
        task = project.ai_tasks.create!(
          instruction: instruction,
          start_url: start_url,
          model: args[:model] || project.default_llm_model,
          browser_provider: args[:browser_provider] || project.default_browser_provider,
          max_steps: args[:max_steps] || 30,
          timeout_seconds: args[:timeout_seconds] || 300,
          metadata: { extraction_schema: args[:extraction_schema] }.compact,
          viewport: { width: 1280, height: 720 }
        )

        if wait
          # Execute synchronously for MCP
          executor = Ai::TaskExecutor.new(task)
          executor.execute!

          task.reload

          success({
            task_id: task.id,
            status: task.status,
            instruction: task.instruction,
            steps_executed: task.steps_executed,
            result: task.result,
            extracted_data: task.extracted_data,
            final_url: task.final_url,
            duration_ms: task.duration_ms,
            error: task.error_message
          })
        else
          # Queue for async execution
          TaskExecutorJob.perform_later(task.id)

          success({
            task_id: task.id,
            status: "queued",
            instruction: task.instruction,
            message: "Task queued for execution. Poll /api/v1/tasks/#{task.id} for status."
          })
        end
      rescue => e
        error("Failed to execute task: #{e.message}")
      end
    end
  end
end
