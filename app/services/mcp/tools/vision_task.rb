# frozen_string_literal: true

module Mcp
  module Tools
    # Execute an autonomous multi-step AI browser task
    class VisionTask < Base
      DESCRIPTION = "Execute an autonomous browser task with AI. The AI agent will navigate, click, type, and extract data to complete your instruction. Supports credential injection for authenticated tasks via Vault integration."

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
          credential: {
            type: "string",
            description: "Name of stored credential to use for login (e.g., 'github', 'aws-console'). Credentials are securely stored in Vault."
          },
          auto_login: {
            type: "boolean",
            default: true,
            description: "Automatically perform login using the credential before starting the main task"
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
        credential_name = args[:credential]
        auto_login = args.fetch(:auto_login, true)

        # Look up credential if specified
        credential = nil
        if credential_name.present?
          credential = project.find_credential(credential_name)
          return error("Credential '#{credential_name}' not found") unless credential

          # Use credential's service URL as start_url if not specified
          start_url ||= credential.login_selectors[:login_url]
        end

        # Modify instruction if we're doing auto-login
        final_instruction = instruction
        if credential && auto_login
          final_instruction = "NOTE: You have been automatically logged in. Do NOT try to login again. " \
                             "Proceed directly with the task: #{instruction}"
        end

        # Create the task
        task = project.ai_tasks.create!(
          instruction: final_instruction,
          start_url: start_url,
          model: args[:model] || project.default_llm_model,
          browser_provider: args[:browser_provider] || project.default_browser_provider,
          max_steps: args[:max_steps] || 30,
          timeout_seconds: args[:timeout_seconds] || 300,
          metadata: {
            extraction_schema: args[:extraction_schema],
            credential_id: credential&.id,
            auto_login: auto_login && credential.present?,
            original_instruction: instruction
          }.compact,
          viewport: { width: 1280, height: 720 }
        )

        if wait
          # Execute synchronously for MCP
          executor = Ai::TaskExecutor.new(task)

          # Register pre-execution callback for credential login
          if credential && auto_login
            executor.before_execute do |browser, session|
              perform_credential_login(task, credential, browser, session)
            end
          end

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
            credential_used: credential&.name,
            error: task.error_message
          })
        else
          # Queue for async execution
          TaskExecutorJob.perform_later(task.id)

          success({
            task_id: task.id,
            status: "queued",
            instruction: task.instruction,
            credential_used: credential&.name,
            message: "Task queued for execution. Poll /api/v1/tasks/#{task.id} for status."
          })
        end
      rescue VaultClient::VaultError => e
        error("Vault error: #{e.message}")
      rescue => e
        error("Failed to execute task: #{e.message}")
      end

      private

      def perform_credential_login(task, credential, browser = nil, session = nil)
        browser ||= BrowserProviders::Factory.for_project(project, provider_override: task.browser_provider)
        session_id = session&.provider_session_id || task.browser_session&.provider_session_id

        return unless session_id

        injector = Ai::CredentialInjector.new(
          browser: browser,
          session_id: session_id,
          project: project
        )

        result = injector.login(credential, navigate: false, submit: true)

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
  end
end
