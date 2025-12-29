# frozen_string_literal: true

module Mcp
  module Tools
    # Conversational AI agent for browser automation
    # Uses a think-observe-decide-act loop with step-by-step reasoning
    class VisionAgent < Base
      DESCRIPTION = "Run a conversational AI agent that thinks step-by-step. " \
                    "The agent observes the page, thinks about what to do, and acts with confidence scoring. " \
                    "It can ask for help when uncertain and provides detailed reasoning for each action."

      SCHEMA = {
        type: "object",
        properties: {
          instruction: {
            type: "string",
            description: "What you want the agent to do (e.g., 'Find and click the ownership checkbox')"
          },
          start_url: {
            type: "string",
            description: "URL to start from"
          },
          credential: {
            type: "string",
            description: "Name of stored credential for authenticated tasks"
          },
          max_steps: {
            type: "integer",
            description: "Maximum steps before stopping (default: 20)"
          }
        },
        required: ["instruction"]
      }.freeze

      def call(args)
        instruction = args[:instruction]
        start_url = args[:start_url]
        credential_name = args[:credential]
        max_steps = args[:max_steps] || 20

        return error("instruction is required") if instruction.blank?

        # Find credential if specified
        credential = nil
        if credential_name.present?
          credential = project.find_credential(credential_name)
          return error("Credential '#{credential_name}' not found") unless credential
        end

        # Create the task record
        task = project.ai_tasks.create!(
          instruction: instruction,
          start_url: start_url || credential&.login_selectors&.dig(:login_url),
          model: args[:model] || project.default_llm_model,
          browser_provider: args[:browser_provider] || project.default_browser_provider,
          max_steps: max_steps,
          timeout_seconds: 300,
          metadata: {
            agent_type: "conversational",
            credential_id: credential&.id
          }.compact,
          viewport: { width: 1280, height: 720 }
        )

        # Run synchronously with streaming output
        conversation_log = []
        final_result = nil

        VisionWorkerPool.with_worker do |worker|
          browser = worker.respond_to?(:browser) ? worker.browser : worker
          session = create_session(task, browser)

          # Navigate to start URL
          if task.start_url.present?
            browser.navigate(session.provider_session_id, task.start_url)
            sleep(1)
          end

          # Handle credential login if needed
          if credential
            perform_login(credential, browser, session)
            # Navigate back to target after login
            if task.start_url.present? && task.start_url != credential.login_selectors[:login_url]
              browser.navigate(session.provider_session_id, task.start_url)
              sleep(1)
            end
          end

          # Create and run the conversational agent
          agent = Ai::ConversationalAgent.new(task, browser: browser, session: session)

          # Capture all agent output
          agent.on_thought do |thought|
            entry = format_thought(thought)
            conversation_log << entry
            Rails.logger.info "[Agent] #{entry}"
          end

          agent.on_action do |action|
            entry = format_action(action)
            conversation_log << entry
            Rails.logger.info "[Agent] #{entry}"
          end

          agent.on_question do |question|
            entry = "❓ #{question[:message]}"
            conversation_log << entry
            Rails.logger.info "[Agent] #{entry}"
            # For now, auto-continue (later: integrate with user interaction)
            agent.answer!("continue")
          end

          agent.on_complete do |result|
            final_result = result
          end

          # Run the agent
          agent.run!

          # Cleanup
          browser.close_session(session.provider_session_id) rescue nil
        end

        # Return the conversation and result
        success(
          task_id: task.id,
          status: task.reload.status,
          result: final_result&.dig(:result) || task.result,
          steps: final_result&.dig(:steps) || task.steps_executed,
          conversation: conversation_log,
          final_url: task.final_url
        )
      rescue => e
        Rails.logger.error "[VisionAgent] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error("Agent error: #{e.message}")
      end

      private

      def create_session(task, browser)
        session_result = browser.create_session(
          viewport: task.viewport,
          headless: true
        )

        project.browser_sessions.create!(
          provider_session_id: session_result[:session_id],
          browser_provider: task.browser_provider,
          status: "active",
          start_url: task.start_url,
          viewport: task.viewport
        )
      end

      def perform_login(credential, browser, session)
        injector = Ai::CredentialInjector.new(
          browser: browser,
          session_id: session.provider_session_id,
          project: project
        )
        injector.login(credential, navigate: true, submit: true)
      end

      def format_thought(thought)
        case thought[:type]
        when :start
          "🚀 #{thought[:message]}"
        when :observing
          "🔍 #{thought[:message]}"
        when :observed
          "👁️ #{thought[:message]}"
        when :thinking
          "💭 #{thought[:message]}"
        when :decided
          confidence_emoji = thought[:confidence] >= 80 ? "✅" : thought[:confidence] >= 50 ? "🤔" : "❓"
          "#{confidence_emoji} [#{thought[:confidence]}%] #{thought[:message]}"
        when :resolved
          "📍 #{thought[:message]}"
        when :warning
          "⚠️ #{thought[:message]}"
        when :stuck
          "🔄 #{thought[:message]}"
        when :limit
          "⏱️ #{thought[:message]}"
        when :stopped
          "🛑 #{thought[:message]}"
        else
          "💬 #{thought[:message]}"
        end
      end

      def format_action(action)
        target = action[:target] || action[:ref] || "page"
        value_text = action[:value] ? " with '#{action[:value]}'" : ""
        "🎯 Action: #{action[:type]} on #{target}#{value_text}"
      end
    end
  end
end
