# frozen_string_literal: true

module Mcp
  module Tools
    # Execute a single AI-powered browser action
    class VisionAiAction < Base
      DESCRIPTION = "Execute a single AI-powered action on a web page. The AI analyzes the page and performs the appropriate action (click, type, etc.)."

      SCHEMA = {
        type: "object",
        properties: {
          instruction: {
            type: "string",
            description: "Natural language action instruction (e.g., 'Click the login button', 'Fill in the email field with test@example.com')"
          },
          session_id: {
            type: "string",
            description: "Existing browser session ID. If not provided, a new session is created."
          },
          url: {
            type: "string",
            description: "URL to navigate to (required if no session_id)"
          },
          model: {
            type: "string",
            enum: %w[claude-sonnet-4 claude-opus-4 gpt-4o gpt-4o-mini gemini-2.5-flash gemini-2.0-flash],
            default: "claude-sonnet-4",
            description: "LLM model to use"
          },
          browser_provider: {
            type: "string",
            enum: %w[local hyperbrowser browserbase stagehand director],
            default: "local",
            description: "Browser provider (only used if creating new session)"
          },
          keep_session: {
            type: "boolean",
            default: false,
            description: "Keep the browser session open after action (returns session_id for reuse)"
          }
        },
        required: %w[instruction]
      }.freeze

      def call(args)
        instruction = args[:instruction]
        session_id = args[:session_id]
        url = args[:url]
        keep_session = args.fetch(:keep_session, false)

        # Use worker pool for quick one-off AI actions (no session_id, not keeping session)
        if session_id.blank? && !keep_session
          return execute_with_worker_pool(instruction, url, args[:model])
        end

        # For persistent sessions, use BrowserSessionManager
        manager = BrowserSessionManager.new(project)

        if session_id.present?
          session = project.browser_sessions.find(session_id)
        else
          raise ArgumentError, "Either session_id or url is required" unless url.present?

          session = manager.create_session(
            provider: args[:browser_provider] || project.default_browser_provider,
            start_url: url,
            viewport: { width: 1280, height: 720 }
          )
        end

        # Get browser and LLM
        browser = manager.provider_for(session)
        llm = LlmProviders::Factory.for_project(
          project,
          model: args[:model] || project.default_llm_model
        )

        # Navigate to URL if provided and different
        if url.present? && browser.current_url(session.provider_session_id) != url
          browser.navigate(session.provider_session_id, url)
          sleep(0.5) # Wait for page load
        end

        # Execute the AI action
        executor = Ai::ActionExecutor.new(
          browser: browser,
          session_id: session.provider_session_id,
          llm: llm,
          project: project
        )

        result = executor.execute(instruction)

        # Update session state
        if result[:url]
          session.update_state!(url: result[:url])
        end

        # Close session unless keeping
        unless keep_session
          manager.close_session(session)
          session = nil
        end

        response = {
          success: result[:success] != false,
          action: result[:action],
          selector: result[:selector],
          value: result[:value],
          url: result[:url],
          reasoning: result[:reasoning],
          error: result[:error]
        }

        if keep_session && session
          response[:session_id] = session.id
        end

        success(response)
      rescue ActiveRecord::RecordNotFound
        error("Session not found: #{session_id}")
      rescue => e
        error("Failed to execute AI action: #{e.message}")
      end

      private

      # Execute AI action using worker pool for fast, stateless operations
      def execute_with_worker_pool(instruction, url, model)
        raise ArgumentError, "url is required for new AI actions" unless url.present?

        result = nil

        VisionWorkerPool.with_worker do |worker|
          # Navigate to URL
          worker.navigate(worker.session_id, url)
          sleep(0.5) # Wait for page load

          # Get LLM
          llm = LlmProviders::Factory.for_project(
            project,
            model: model || project.default_llm_model
          )

          # Execute the AI action using the worker as browser
          executor = Ai::ActionExecutor.new(
            browser: worker,
            session_id: worker.session_id,
            llm: llm,
            project: project
          )

          result = executor.execute(instruction)
        end

        success({
          success: result[:success] != false,
          action: result[:action],
          selector: result[:selector],
          value: result[:value],
          url: result[:url],
          reasoning: result[:reasoning],
          error: result[:error],
          pooled: true  # Indicates worker pool was used
        })
      end
    end
  end
end
