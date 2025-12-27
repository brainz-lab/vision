# frozen_string_literal: true

module Mcp
  module Tools
    # Execute direct browser actions (no AI inference)
    class VisionPerform < Base
      DESCRIPTION = "Execute direct browser actions like click, type, navigate, etc. Use this for precise control when you know exactly what action to take."

      SCHEMA = {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: %w[navigate click fill type select hover scroll wait press clear check uncheck],
            description: "Action to perform"
          },
          selector: {
            type: "string",
            description: "CSS selector for the target element (for click, fill, type, select, hover, check, uncheck)"
          },
          value: {
            type: "string",
            description: "Value for the action (URL for navigate, text for fill/type, option for select, key for press, pixels/direction for scroll)"
          },
          session_id: {
            type: "string",
            description: "Existing browser session ID. If not provided, a new session is created."
          },
          url: {
            type: "string",
            description: "Starting URL (required if no session_id and action is not navigate)"
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
            description: "Keep the browser session open after action"
          },
          wait_after: {
            type: "integer",
            default: 0,
            description: "Milliseconds to wait after action"
          }
        },
        required: %w[action]
      }.freeze

      def call(args)
        action = args[:action].to_sym
        selector = args[:selector]
        value = args[:value]
        session_id = args[:session_id]
        url = args[:url]
        keep_session = args.fetch(:keep_session, false)
        wait_after = args[:wait_after] || 0

        # Validate required parameters
        validate_params!(action, selector, value)

        # Get or create session
        manager = BrowserSessionManager.new(project)

        if session_id.present?
          session = project.browser_sessions.find(session_id)
        else
          start_url = action == :navigate ? value : url
          raise ArgumentError, "url is required when creating a new session" unless start_url.present?

          session = manager.create_session(
            provider: args[:browser_provider] || project.default_browser_provider,
            start_url: start_url,
            viewport: { width: 1280, height: 720 }
          )
        end

        browser = manager.provider_for(session)

        # Navigate to URL first if needed (and action is not navigate itself)
        if url.present? && action != :navigate
          current = browser.current_url(session.provider_session_id)
          if current != url
            browser.navigate(session.provider_session_id, url)
            sleep(0.5)
          end
        end

        # Execute the action
        result = execute_action(browser, session, action, selector, value)

        # Wait if requested
        if wait_after > 0
          sleep(wait_after / 1000.0)
        end

        # Update session state
        new_url = browser.current_url(session.provider_session_id) rescue nil
        if new_url
          session.update_state!(url: new_url)
        end

        # Close session unless keeping
        unless keep_session
          manager.close_session(session)
          session = nil
        end

        response = {
          success: result[:success] != false,
          action: action.to_s,
          selector: selector,
          value: value,
          url: new_url,
          error: result[:error]
        }

        if keep_session && session
          response[:session_id] = session.id
        end

        success(response)
      rescue ActiveRecord::RecordNotFound
        error("Session not found: #{session_id}")
      rescue ArgumentError => e
        error(e.message)
      rescue => e
        error("Failed to perform action: #{e.message}")
      end

      private

      def validate_params!(action, selector, value)
        case action
        when :navigate
          raise ArgumentError, "value (URL) is required for navigate action" unless value.present?
        when :click, :hover, :check, :uncheck
          raise ArgumentError, "selector is required for #{action} action" unless selector.present?
        when :fill, :type
          raise ArgumentError, "selector is required for #{action} action" unless selector.present?
          raise ArgumentError, "value is required for #{action} action" unless value.present?
        when :select
          raise ArgumentError, "selector is required for select action" unless selector.present?
          raise ArgumentError, "value (option) is required for select action" unless value.present?
        when :press
          raise ArgumentError, "value (key) is required for press action" unless value.present?
        when :scroll, :wait, :clear
          # No required params
        end
      end

      def execute_action(browser, session, action, selector, value)
        session_id = session.provider_session_id

        case action
        when :navigate
          browser.navigate(session_id, value)
        when :click
          browser.perform_action(session_id, action: :click, selector: selector)
        when :fill, :type
          browser.perform_action(session_id, action: :fill, selector: selector, value: value)
        when :select
          browser.perform_action(session_id, action: :select, selector: selector, value: value)
        when :hover
          browser.perform_action(session_id, action: :hover, selector: selector)
        when :scroll
          browser.perform_action(session_id, action: :scroll, value: value || "down")
        when :wait
          sleep((value || 1000).to_i / 1000.0)
          { success: true }
        when :press
          browser.perform_action(session_id, action: :press, value: value)
        when :clear
          browser.perform_action(session_id, action: :clear, selector: selector)
        when :check
          browser.perform_action(session_id, action: :check, selector: selector)
        when :uncheck
          browser.perform_action(session_id, action: :uncheck, selector: selector)
        else
          { success: false, error: "Unknown action: #{action}" }
        end
      end
    end
  end
end
