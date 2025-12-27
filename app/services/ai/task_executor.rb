# frozen_string_literal: true

module Ai
  # Core AI task executor that orchestrates browser automation
  # Main execution loop: capture state -> LLM decision -> execute action -> repeat
  class TaskExecutor
    MAX_CONSECUTIVE_FAILURES = 3

    attr_reader :task, :project, :llm, :browser, :session

    def initialize(task)
      @task = task
      @project = task.project
      @callbacks = { step: [], progress: [], complete: [] }
      @consecutive_failures = 0
    end

    # Register callbacks for progress updates
    def on_step(&block)
      @callbacks[:step] << block
    end

    def on_progress(&block)
      @callbacks[:progress] << block
    end

    def on_complete(&block)
      @callbacks[:complete] << block
    end

    # Execute the task
    # @return [AiTask] The updated task
    def execute!
      setup!
      task.start!

      begin
        # Navigate to starting URL
        if task.start_url.present?
          @browser.navigate(@session.provider_session_id, task.start_url)
          @session.update_state!(url: task.start_url)
          capture_screenshot(0, "initial")
        end

        # Main execution loop
        step_count = 0
        while step_count < task.max_steps && !task.stop_requested?
          step_count += 1

          # Capture current state
          state = capture_state

          # Ask LLM for next action
          decision = decide_next_action(state)

          # Check if task is complete
          if decision[:complete]
            task.complete!(result_text: decision[:result])
            break
          end

          # Execute the action
          action = decision[:action]
          step = execute_step(action, step_count, decision[:reasoning])

          notify_step(step)
          notify_progress(step_count, action[:type])

          # Track failures
          if step.success?
            @consecutive_failures = 0
          else
            @consecutive_failures += 1
            if @consecutive_failures >= MAX_CONSECUTIVE_FAILURES
              task.fail!("Too many consecutive failures")
              break
            end
          end

          # Small delay between actions
          sleep(0.3)
        end

        # Handle completion states
        if step_count >= task.max_steps && !task.finished?
          task.update!(
            status: "completed",
            result: "Reached maximum steps (#{task.max_steps})",
            final_url: current_url,
            completed_at: Time.current,
            duration_ms: calculate_duration
          )
        elsif task.stop_requested? && !task.finished?
          task.stop!(reason: "Stopped by user request")
        end

        notify_complete

        task
      rescue => e
        Rails.logger.error "TaskExecutor error: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
        task.fail!(e)
        raise
      ensure
        cleanup!
      end
    end

    private

    def setup!
      # Initialize LLM provider
      @llm = LlmProviders::Factory.for_project(project, model: task.model)

      # Initialize browser provider
      @browser = BrowserProviders::Factory.for_project(project, provider_override: task.browser_provider)

      # Create browser session
      session_result = @browser.create_session(
        viewport: task.viewport,
        headless: true
      )

      @session = project.browser_sessions.create!(
        provider_session_id: session_result[:session_id],
        browser_provider: task.browser_provider,
        status: "active",
        start_url: task.start_url,
        viewport: task.viewport,
        metadata: session_result.except(:session_id, :provider)
      )

      # Link session to task for isolation tracking
      task.update!(browser_session: @session)
    end

    def cleanup!
      if @session && @browser
        begin
          @browser.close_session(@session.provider_session_id)
          @session.close!
        rescue => e
          Rails.logger.warn "Failed to cleanup session: #{e.message}"
        end
      end
    end

    def capture_state
      screenshot_result = @browser.screenshot(@session.provider_session_id, full_page: false)
      html = @browser.page_content(@session.provider_session_id, format: :html)

      {
        url: current_url,
        title: @browser.current_title(@session.provider_session_id),
        screenshot: screenshot_result[:data],
        html: html,
        interactive_elements: extract_interactive_elements(html)
      }
    end

    def current_url
      @browser.current_url(@session.provider_session_id)
    rescue
      @session.current_url
    end

    def decide_next_action(state)
      # Build the prompt for the LLM
      prompt = build_action_prompt(state)

      # Get LLM decision with vision
      response = @llm.analyze_image(
        image_data: state[:screenshot],
        prompt: prompt,
        format: :binary
      )

      # Parse the response
      parse_llm_decision(response[:text])
    end

    def build_action_prompt(state)
      previous_steps = task.steps.ordered.last(5).map do |s|
        "- #{s.action}: #{s.selector || s.value} (#{s.success? ? 'success' : 'failed'})"
      end.join("\n")

      <<~PROMPT
        You are a browser automation agent. Your task is:
        #{task.instruction}

        Current page: #{state[:url]}
        Title: #{state[:title]}
        Steps taken: #{task.steps_executed}

        #{previous_steps.present? ? "Recent actions:\n#{previous_steps}" : ""}

        Interactive elements on page:
        #{state[:interactive_elements].first(30).map { |e| "#{e[:index]}. #{e[:tag]} - #{e[:text].to_s.truncate(40)}" }.join("\n")}

        Analyze the screenshot and determine the next action.

        Respond with JSON only:
        {
          "thinking": "your reasoning about the current state and what to do next",
          "action": {
            "type": "click|type|fill|navigate|scroll|hover|select|wait|press",
            "selector": "CSS selector or element index (e.g., '#submit' or 'button:has-text(\"Login\")')",
            "value": "value for type/fill/navigate actions"
          },
          "complete": false,
          "result": null
        }

        Set "complete": true and provide "result" when the task is finished.
        Set "action.type": "wait" with "value": "1000" to wait 1 second if page is loading.

        Important:
        - Use specific selectors from the interactive elements list
        - For buttons/links, use text content: button:has-text("Submit")
        - For inputs, use labels or placeholders: input[placeholder="Email"]
        - If stuck, try scrolling or waiting
      PROMPT
    end

    def parse_llm_decision(text)
      # Try to extract JSON from the response
      json_match = text.match(/\{[\s\S]*\}/)
      return { complete: false, action: { type: "wait", value: "1000" }, reasoning: "Failed to parse LLM response" } unless json_match

      data = JSON.parse(json_match[0], symbolize_names: true)

      {
        thinking: data[:thinking],
        action: data[:action]&.symbolize_keys || { type: "wait", value: "1000" },
        complete: data[:complete] == true,
        result: data[:result],
        reasoning: data[:thinking]
      }
    rescue JSON::ParserError => e
      Rails.logger.warn "Failed to parse LLM response: #{e.message}"
      { complete: false, action: { type: "wait", value: "1000" }, reasoning: "JSON parse error" }
    end

    def execute_step(action, position, reasoning = nil)
      url_before = current_url
      start_time = Time.current

      # Execute the action
      result = case action[:type].to_sym
      when :navigate
        @browser.navigate(@session.provider_session_id, action[:value])
      else
        @browser.perform_action(
          @session.provider_session_id,
          action: action[:type],
          selector: action[:selector],
          value: action[:value]
        )
      end

      duration_ms = ((Time.current - start_time) * 1000).to_i
      url_after = current_url

      # Update session state
      @session.update_state!(url: url_after) if url_after != url_before

      # Create step record
      step = task.steps.create!(
        position: position,
        action: action[:type],
        selector: action[:selector],
        value: action[:value],
        action_data: action,
        success: result[:success] != false,
        error_message: result[:error],
        duration_ms: duration_ms,
        url_before: url_before,
        url_after: url_after,
        reasoning: reasoning,
        executed_at: Time.current
      )

      # Capture screenshot after action
      if task.capture_screenshots?
        capture_screenshot(position, action[:type])
      end

      # Update task counters
      task.increment_steps!

      # Cache successful action for replay
      if step.success?
        ActionCacheEntry.store(
          project: project,
          url: url_before,
          action: action[:type],
          action_data: action,
          instruction: task.instruction
        )
      end

      step
    end

    def capture_screenshot(step_index, label)
      screenshot_result = @browser.screenshot(@session.provider_session_id, full_page: false)

      task.screenshots.attach(
        io: StringIO.new(screenshot_result[:data]),
        filename: "task_#{task.id}_step_#{step_index}_#{label}.png",
        content_type: "image/png"
      )
    rescue => e
      Rails.logger.warn "Failed to capture screenshot: #{e.message}"
    end

    def extract_interactive_elements(html)
      # Parse HTML and find interactive elements
      doc = Nokogiri::HTML(html)
      elements = []

      selectors = "a, button, input, select, textarea, [role='button'], [onclick], [tabindex]"
      doc.css(selectors).each_with_index do |el, idx|
        next if el["hidden"] || el["style"]&.include?("display: none")

        elements << {
          index: idx + 1,
          tag: el.name,
          type: el["type"],
          text: el.text.strip.truncate(50),
          placeholder: el["placeholder"],
          aria_label: el["aria-label"],
          id: el["id"],
          name: el["name"],
          href: el["href"]
        }
      end

      elements
    rescue => e
      Rails.logger.warn "Failed to extract elements: #{e.message}"
      []
    end

    def calculate_duration
      return nil unless task.started_at

      ((Time.current - task.started_at) * 1000).to_i
    end

    def notify_step(step)
      @callbacks[:step].each { |cb| cb.call(step) }
    end

    def notify_progress(step_count, action)
      @callbacks[:progress].each do |cb|
        cb.call({ steps_executed: step_count, current_action: action })
      end
    end

    def notify_complete
      @callbacks[:complete].each { |cb| cb.call(task) }
    end
  end
end
