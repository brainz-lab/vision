# frozen_string_literal: true

module Ai
  # Conversational AI agent for browser automation
  # Uses a think-observe-decide-act loop with confidence scoring
  # Can pause and ask user for guidance when uncertain
  #
  # Usage:
  #   agent = ConversationalAgent.new(task, browser: browser, session: session)
  #   agent.on_thought { |thought| puts thought }
  #   agent.on_question { |q| get_user_answer(q) }
  #   agent.run!
  #
  class ConversationalAgent
    # Confidence thresholds
    HIGH_CONFIDENCE = 80
    MEDIUM_CONFIDENCE = 50

    # Stopping conditions
    MAX_STEPS = 20
    MAX_SAME_STATE = 3

    attr_reader :task, :project, :browser, :session, :conversation

    def initialize(task, browser:, session:)
      @task = task
      @project = task.project
      @browser = browser
      @session = session
      @llm = LlmProviders::Factory.for_project(project, model: task.model)

      @conversation = []  # Full conversation history
      @state_history = [] # Track states to detect being stuck
      @step_count = 0
      @stopped = false

      # Callbacks
      @callbacks = {
        thought: [],      # Called when agent thinks/observes
        action: [],       # Called when agent acts
        question: [],     # Called when agent needs user input
        complete: [],     # Called when task completes
        error: []         # Called on errors
      }
    end

    # Register callbacks
    def on_thought(&block); @callbacks[:thought] << block; end
    def on_action(&block); @callbacks[:action] << block; end
    def on_question(&block); @callbacks[:question] << block; end
    def on_complete(&block); @callbacks[:complete] << block; end
    def on_error(&block); @callbacks[:error] << block; end

    # Main execution loop
    def run!
      emit(:thought, type: :start, message: "Starting task: #{task.instruction}")

      # Initial observation
      observe!

      while !@stopped && @step_count < MAX_STEPS
        @step_count += 1

        # Think about what to do
        decision = think!

        # Check if we should stop
        if decision[:complete]
          complete!(decision[:result])
          break
        end

        # Check confidence level
        if decision[:confidence] < MEDIUM_CONFIDENCE
          # Low confidence - ask user
          answer = ask_user!(decision)
          next if answer == :retry  # User gave guidance, retry thinking
          break if answer == :stop  # User wants to stop
        end

        # Execute the action
        result = act!(decision)

        # Check if stuck
        if stuck?
          emit(:thought, type: :stuck, message: "I seem to be stuck - same state for #{MAX_SAME_STATE} steps")
          answer = ask_user!(type: :stuck, options: ["Keep trying", "Give me a hint", "Stop"])
          break if answer == :stop
        end

        # Brief pause between steps
        sleep(0.5)
      end

      if @step_count >= MAX_STEPS && !@stopped
        emit(:thought, type: :limit, message: "Reached step limit (#{MAX_STEPS})")
        complete!("Reached step limit without completing task")
      end

      task
    end

    # Stop the agent
    def stop!
      @stopped = true
      emit(:thought, type: :stopped, message: "Agent stopped by user")
    end

    # Provide answer to agent's question
    def answer!(response)
      @pending_answer = response
    end

    private

    def session_id
      @session.provider_session_id
    end

    # Observe current page state
    def observe!
      emit(:thought, type: :observing, message: "Observing page...")

      # Take screenshot
      screenshot = @browser.screenshot(session_id, full_page: false)

      # Get page info
      url = @browser.current_url(session_id)
      title = @browser.current_title(session_id)

      # Extract interactive elements
      elements = @browser.extract_elements_with_refs(session_id)

      @current_state = {
        url: url,
        title: title,
        screenshot: screenshot[:data],
        elements: elements[:elements],
        viewport: elements[:viewport],
        timestamp: Time.current
      }

      # Track state for stuck detection
      state_signature = "#{url}|#{elements[:elements].map { |e| e[:ref] }.join(',')}"
      @state_history << state_signature
      @state_history = @state_history.last(MAX_SAME_STATE + 1)

      # Emit observation
      element_summary = summarize_elements(elements[:elements])
      emit(:thought, type: :observed, message: "Page: #{title}\nURL: #{url}\n#{element_summary}")

      @current_state
    end

    # Think about what to do next
    def think!
      emit(:thought, type: :thinking, message: "Thinking...")

      prompt = build_thinking_prompt

      response = @llm.analyze_image(
        image_data: @current_state[:screenshot],
        prompt: prompt,
        format: :binary
      )

      decision = parse_thinking_response(response[:text])

      # Add to conversation
      @conversation << {
        role: :assistant,
        type: :thought,
        content: decision[:thinking],
        decision: decision
      }

      emit(:thought,
        type: :decided,
        message: decision[:thinking],
        confidence: decision[:confidence],
        action: decision[:action]
      )

      decision
    end

    # Execute an action
    def act!(decision)
      action = decision[:action]
      action_type = action[:type].to_s

      emit(:action,
        type: action_type,
        target: action[:ref] || action[:selector],
        value: action[:value],
        confidence: decision[:confidence]
      )

      # Only resolve refs for click/type actions (not scroll/wait)
      needs_ref = %w[click type].include?(action_type) && action[:ref].present?

      if needs_ref
        # Re-observe before acting to get fresh coordinates
        observe!

        # Resolve ref to coordinates
        element = @current_state[:elements].find { |e| e[:ref].to_s.upcase == action[:ref].to_s.upcase }
        if element
          action[:x] = element[:x]
          action[:y] = element[:y]
          emit(:thought, type: :resolved, message: "Resolved #{action[:ref]} to (#{action[:x]}, #{action[:y]})")
        else
          emit(:thought, type: :warning, message: "Could not find element #{action[:ref]}")
          return { success: false, error: "Element not found: #{action[:ref]}" }
        end
      end

      # Execute the action
      result = execute_action(action)

      # Wait for page to settle
      sleep(1)

      # Re-observe after action
      observe!

      result
    end

    def execute_action(action)
      case action[:type].to_s
      when "click"
        if action[:x] && action[:y]
          @browser.perform_action(session_id, action: :click, x: action[:x], y: action[:y])
        elsif action[:selector]
          @browser.perform_action(session_id, action: :click, selector: action[:selector])
        end
      when "type"
        if action[:ref] && action[:x] && action[:y]
          # Click first, then type
          @browser.perform_action(session_id, action: :click, x: action[:x], y: action[:y])
          sleep(0.3)
          @browser.perform_action(session_id, action: :type, selector: "body", value: action[:value])
        elsif action[:selector]
          @browser.perform_action(session_id, action: :type, selector: action[:selector], value: action[:value])
        end
      when "scroll"
        @browser.perform_action(session_id, action: :scroll, value: action[:value] || "page_down")
      when "wait"
        sleep((action[:value] || 1000).to_i / 1000.0)
        { success: true }
      else
        { success: false, error: "Unknown action type: #{action[:type]}" }
      end
    rescue => e
      { success: false, error: e.message }
    end

    # Ask user for guidance
    def ask_user!(context)
      question = build_question(context)

      emit(:question,
        message: question[:message],
        options: question[:options],
        context: context
      )

      # Wait for answer (this would be async in real implementation)
      # For now, we'll use the callback system
      @pending_answer = nil

      # The callback handler should call agent.answer!(response)
      # For sync execution, we need to block here
      # In async/streaming mode, this would yield control

      wait_for_answer(timeout: 60)

      process_answer(@pending_answer, context)
    end

    def wait_for_answer(timeout:)
      start = Time.current
      while @pending_answer.nil? && (Time.current - start) < timeout
        sleep(0.1)
      end
    end

    def process_answer(answer, context)
      return :stop if answer.nil? || answer.to_s.downcase == "stop"

      # Add user's answer to conversation
      @conversation << {
        role: :user,
        type: :answer,
        content: answer
      }

      if answer.to_s.downcase.include?("keep") || answer.to_s.downcase.include?("continue")
        :continue
      elsif answer.to_s.downcase.include?("stop") || answer.to_s.downcase.include?("cancel")
        :stop
      else
        # User gave guidance - add it to context for next think cycle
        :retry
      end
    end

    def build_question(context)
      if context[:type] == :stuck
        {
          message: "I seem to be stuck. What should I do?",
          options: context[:options] || ["Keep trying", "Give me a hint", "Stop"]
        }
      else
        {
          message: "I'm not sure what to do next. #{context[:thinking]}",
          options: ["Try option 1", "Try option 2", "Let me describe more", "Stop"]
        }
      end
    end

    # Mark task as complete
    def complete!(result)
      @stopped = true

      emit(:complete,
        result: result,
        steps: @step_count,
        conversation: @conversation
      )

      task.update!(
        status: "completed",
        result: result,
        steps_executed: @step_count,
        final_url: @current_state&.dig(:url)
      )
    end

    # Check if we're stuck (same state multiple times)
    def stuck?
      return false if @state_history.length < MAX_SAME_STATE
      @state_history.last(MAX_SAME_STATE).uniq.length == 1
    end

    # Build the thinking prompt
    def build_thinking_prompt
      # Recent conversation context
      recent_actions = @conversation.last(5).map do |entry|
        case entry[:type]
        when :thought
          "Thought: #{entry[:content]}"
        when :answer
          "User said: #{entry[:content]}"
        else
          nil
        end
      end.compact.join("\n")

      # Format visible elements
      elements_text = (@current_state[:elements] || []).first(30).map do |el|
        checked = el[:checked] ? " [CHECKED]" : ""
        "#{el[:ref]}: #{el[:type]} \"#{el[:text].to_s.truncate(40)}\"#{checked} at (#{el[:x]}, #{el[:y]})"
      end.join("\n")

      <<~PROMPT
        You are a browser automation agent having a conversation with the user.

        TASK: #{task.instruction}

        CURRENT PAGE:
        URL: #{@current_state[:url]}
        Title: #{@current_state[:title]}
        Step: #{@step_count}/#{MAX_STEPS}

        #{recent_actions.present? ? "RECENT CONTEXT:\n#{recent_actions}\n" : ""}

        VISIBLE ELEMENTS:
        #{elements_text}

        RESPOND WITH JSON:
        {
          "thinking": "What I observe and my reasoning (be conversational, like explaining to a user)",
          "confidence": 85,
          "complete": false,
          "result": null,
          "action": {
            "type": "click|type|scroll|wait",
            "ref": "BTN1",
            "value": "optional value"
          }
        }

        GUIDELINES:
        - Be conversational in your "thinking" - explain what you see and why you're doing something
        - Set "confidence" from 0-100 based on how sure you are this is the right action
        - If confidence < 50, explain your uncertainty so I can help
        - Set "complete": true when the task is done, with "result" explaining what happened
        - Use element refs (BTN1, CHK1, etc.) to specify what to click
        - If you don't see what you need, scroll to find it
        - If task seems impossible, set complete: true with explanation

        ELEMENT TYPES:
        - BTN = button
        - LNK = link
        - IN = input field
        - CHK = checkbox
        - SEL = select dropdown
      PROMPT
    end

    def parse_thinking_response(text)
      json_match = text.match(/\{[\s\S]*\}/)
      return default_decision("Could not parse response") unless json_match

      data = JSON.parse(json_match[0], symbolize_names: true)

      {
        thinking: data[:thinking] || "No explanation provided",
        confidence: (data[:confidence] || 50).to_i,
        complete: data[:complete] || false,
        result: data[:result],
        action: (data[:action] || {}).symbolize_keys
      }
    rescue JSON::ParserError
      default_decision("JSON parse error")
    end

    def default_decision(reason)
      {
        thinking: reason,
        confidence: 0,
        complete: false,
        result: nil,
        action: { type: "wait", value: 1000 }
      }
    end

    def summarize_elements(elements)
      return "No interactive elements found" if elements.empty?

      by_type = elements.group_by { |e| e[:type] }
      summary = by_type.map { |type, els| "#{els.count} #{type}s" }.join(", ")

      # Highlight potentially relevant elements
      relevant = elements.select { |e|
        text = e[:text].to_s.downcase
        text.include?("own") || text.include?("want") || text.include?("have") ||
        text.include?("check") || text.include?("add") || text.include?("save")
      }

      if relevant.any?
        relevant_text = relevant.map { |e| "#{e[:ref]}: \"#{e[:text]}\"" }.join(", ")
        "Elements: #{summary}\nPotentially relevant: #{relevant_text}"
      else
        "Elements: #{summary}"
      end
    end

    def emit(type, **data)
      @callbacks[type].each { |cb| cb.call(data) }
    rescue => e
      Rails.logger.warn "Callback error: #{e.message}"
    end
  end
end
