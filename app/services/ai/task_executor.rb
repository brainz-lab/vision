# frozen_string_literal: true

module Ai
  # Core AI task executor that orchestrates browser automation
  # Main execution loop: capture state -> LLM decision -> execute action -> repeat
  class TaskExecutor
    MAX_CONSECUTIVE_FAILURES = 5  # Increased from 3 for more resilience
    MAX_RETRIES_PER_ACTION = 2

    attr_reader :task, :project, :llm, :browser, :session

    def initialize(task)
      @task = task
      @project = task.project
      @callbacks = { step: [], progress: [], complete: [] }
      @consecutive_failures = 0
      @last_error = nil
      # Batch collections for N+1 optimization
      @pending_screenshots = []
      @pending_cache_entries = []
      @steps_executed_count = 0
      # Preload steps for efficient access during execution
      @cached_steps = []
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

    # Register callback to run before main execution loop (after browser setup and navigation)
    def before_execute(&block)
      @callbacks[:before_execute] ||= []
      @callbacks[:before_execute] << block
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
          queue_screenshot(0, "initial")
        end

        # Clean the page of any obstacles (cookie banners, popups)
        clean_page!

        # Run before_execute callbacks (e.g., credential login)
        if @callbacks[:before_execute]&.any?
          @callbacks[:before_execute].each do |cb|
            cb.call(@browser, @session)
          end
          # Wait for any redirects after login
          sleep(2)
          # Clean again after login
          clean_page!

          # Navigate back to start_url after login (site may have redirected)
          if task.start_url.present?
            current = @browser.current_url(@session.provider_session_id)
            unless current&.include?(URI.parse(task.start_url).path)
              Rails.logger.info "[TaskExecutor] Navigating back to start_url after login: #{task.start_url}"
              @browser.navigate(@session.provider_session_id, task.start_url)
              sleep(1)
              clean_page!
            end
          end
        end

        # Main execution loop
        step_count = 0
        while step_count < task.max_steps && !task.stop_requested?
          step_count += 1

          # Capture current state
          state = capture_state
          Rails.logger.info "[TaskExecutor] Step #{step_count}/#{task.max_steps} - URL: #{state[:url]}"

          # Ask LLM for next action
          decision = decide_next_action(state)
          Rails.logger.info "[TaskExecutor] Decision: #{decision[:action][:type]} - #{decision[:action][:selector]&.truncate(50) || decision[:action][:value]}"
          Rails.logger.info "[TaskExecutor] Reasoning: #{decision[:reasoning]&.truncate(100)}"

          # Check if task is complete
          if decision[:complete]
            Rails.logger.info "[TaskExecutor] Task marked complete: #{decision[:result]}"
            flush_pending_operations!
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
              error_details = @last_error ? " (Last error: #{@last_error})" : ""
              flush_pending_operations!
              task.fail!("Too many consecutive failures (#{@consecutive_failures})#{error_details}")
              break
            end
          end

          # Flush pending operations periodically (every 5 steps)
          flush_pending_operations! if step_count % 5 == 0

          # Periodically clean page of new popups/banners (every 10 steps)
          clean_page! if step_count % 10 == 0

          # Small delay between actions
          sleep(0.3)
        end

        # Flush any remaining pending operations
        flush_pending_operations!

        # Handle completion states
        if step_count >= task.max_steps && !task.finished?
          task.update!(
            status: "completed",
            result: "Reached maximum steps (#{task.max_steps})",
            final_url: current_url,
            completed_at: Time.current,
            duration_ms: calculate_duration,
            steps_executed: @steps_executed_count
          )
        elsif task.stop_requested? && !task.finished?
          task.stop!(reason: "Stopped by user request")
        end

        notify_complete

        task
      rescue => e
        Rails.logger.error "TaskExecutor error: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
        flush_pending_operations! rescue nil
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
      # Use cached steps to avoid N+1 query - get last 5 from cache
      previous_steps = @cached_steps.last(5).map do |s|
        "- #{s[:action]}: #{s[:selector] || s[:value]} (#{s[:success] ? 'success' : 'failed'})"
      end.join("\n")

      <<~PROMPT
        You are a browser automation agent. Complete this task:
        #{task.instruction}

        CURRENT STATE:
        URL: #{state[:url]}
        Title: #{state[:title]}
        Steps taken: #{@steps_executed_count} / #{task.max_steps} max

        #{previous_steps.present? ? "Recent actions:\n#{previous_steps}" : ""}

        INTERACTIVE ELEMENTS (index. tag[id/class] - text):
        #{state[:interactive_elements].first(40).map { |e|
          id_class = [e[:id], e[:class]].compact.join(" ").truncate(30)
          "#{e[:index]}. #{e[:tag]}#{id_class.present? ? "[#{id_class}]" : ""} - #{e[:text].to_s.truncate(40)}"
        }.join("\n")}

        RESPOND WITH JSON ONLY:
        {
          "thinking": "brief reasoning about what you see and what to do",
          "action": {
            "type": "click|type|fill|scroll|wait|press",
            "selector": "CSS selector (e.g., '#submit', 'button:has-text(\"Login\")')",
            "value": "for type/fill/scroll actions"
          },
          "complete": false,
          "result": null
        }

        RULES:
        1. FOCUS ON THE TASK - Do not click random links or navigation
        2. STAY ON THIS PAGE unless the task explicitly requires navigation
        3. Look for checkboxes, buttons, or forms related to the task
        4. If you see an "I own this" checkbox or "Mark as owned" button, click it
        5. After clicking a checkbox/button that completes the task, set complete=true
        6. Do NOT click on other set links, random sets, or navigation menus

        SELECTOR SYNTAX:
        - Use Playwright selectors: button:has-text("Submit"), a:has-text("Link")
        - NEVER use :contains() - use :has-text() instead
        - For inputs: input[name="email"], input#id, input.class
        - Keep selectors specific to avoid clicking wrong elements

        SCROLL OPTIONS:
        - "page_down": scroll down one screen
        - "page_up": scroll up one screen
        - scroll_into_view: scroll element into view (needs selector)

        COMPLETION:
        - Set complete=true when the task action is done (e.g., checkbox checked, button clicked)
        - Set complete=true if you've searched the page and the element doesn't exist
        - Provide result describing what was accomplished
      PROMPT
    end

    def parse_llm_decision(text)
      # Try to extract JSON from the response
      json_match = text.match(/\{[\s\S]*\}/)
      return { complete: false, action: { type: "wait", value: "1000" }, reasoning: "Failed to parse LLM response" } unless json_match

      data = JSON.parse(json_match[0], symbolize_names: true)

      action = data[:action]&.symbolize_keys || { type: "wait", value: "1000" }

      # Normalize selector to fix common LLM mistakes
      if action[:selector].present?
        action[:selector] = normalize_selector(action[:selector])
      end

      {
        thinking: data[:thinking],
        action: action,
        complete: data[:complete] == true,
        result: data[:result],
        reasoning: data[:thinking]
      }
    rescue JSON::ParserError => e
      Rails.logger.warn "Failed to parse LLM response: #{e.message}"
      { complete: false, action: { type: "wait", value: "1000" }, reasoning: "JSON parse error" }
    end

    # Normalize selector to fix common LLM mistakes
    def normalize_selector(selector)
      return selector unless selector.is_a?(String)

      # Convert jQuery :contains() to Playwright :has-text()
      # Example: a:contains("text") -> a:has-text("text")
      normalized = selector.gsub(/:contains\((['"])(.*?)\1\)/, ':has-text(\1\2\1)')

      # Fix other common issues
      normalized = normalized.gsub(/:visible/, '') # :visible is not valid
      normalized = normalized.gsub(/\s+$/, '')     # Trim trailing whitespace

      if normalized != selector
        Rails.logger.info "[TaskExecutor] Normalized selector: #{selector} -> #{normalized}"
      end

      normalized
    end

    def execute_step(action, position, reasoning = nil)
      url_before = current_url
      start_time = Time.current
      result = nil
      retries = 0

      # Retry logic for failed actions
      loop do
        begin
          # Execute the action
          result = case action[:type].to_sym
          when :navigate
            @browser.navigate(@session.provider_session_id, action[:value])
          when :scroll_into_view
            @browser.perform_action(
              @session.provider_session_id,
              action: :scroll_into_view,
              selector: action[:selector]
            )
          when :wait
            sleep((action[:value].to_i.positive? ? action[:value].to_i : 1000) / 1000.0)
            { success: true }
          else
            @browser.perform_action(
              @session.provider_session_id,
              action: action[:type],
              selector: action[:selector],
              value: action[:value]
            )
          end

          # Break if successful
          break if result[:success] != false || result[:error].nil?

          # Retry on failure
          retries += 1
          if retries < MAX_RETRIES_PER_ACTION
            Rails.logger.warn "[TaskExecutor] Action #{action[:type]} failed, retrying (#{retries}/#{MAX_RETRIES_PER_ACTION}): #{result[:error]}"
            sleep(0.5)
          else
            Rails.logger.warn "[TaskExecutor] Action #{action[:type]} failed after #{retries} retries: #{result[:error]}"
            break
          end
        rescue => e
          retries += 1
          result = { success: false, error: e.message }

          if retries < MAX_RETRIES_PER_ACTION
            Rails.logger.warn "[TaskExecutor] Action #{action[:type]} raised error, retrying (#{retries}/#{MAX_RETRIES_PER_ACTION}): #{e.message}"
            sleep(0.5)
          else
            Rails.logger.error "[TaskExecutor] Action #{action[:type]} failed after #{retries} retries: #{e.message}"
            break
          end
        end
      end

      duration_ms = ((Time.current - start_time) * 1000).to_i
      url_after = current_url

      # Update session state
      @session.update_state!(url: url_after) if url_after != url_before

      success = result[:success] != false

      # Create step record
      step = task.steps.create!(
        position: position,
        action: action[:type],
        selector: action[:selector],
        value: action[:value],
        action_data: action,
        success: success,
        error_message: result[:error],
        duration_ms: duration_ms,
        url_before: url_before,
        url_after: url_after,
        reasoning: reasoning,
        executed_at: Time.current
      )

      # Cache step data for prompt building (avoid N+1 when building prompts)
      @cached_steps << {
        action: action[:type],
        selector: action[:selector],
        value: action[:value],
        success: success
      }

      # Store last error for debugging
      @last_error = result[:error] if result[:success] == false

      # Queue screenshot for batch attachment (instead of attaching one by one)
      if task.capture_screenshots?
        queue_screenshot(position, action[:type])
      end

      # Increment local counter (batch update to DB later)
      @steps_executed_count += 1

      # Queue cache entry for batch upsert (only cacheable action types)
      if success && ActionCacheEntry::CACHEABLE_ACTIONS.include?(action[:type].to_s)
        queue_cache_entry(
          url: url_before,
          action: action[:type],
          action_data: action
        )
      end

      step
    end

    # Queue screenshot for batch attachment later
    def queue_screenshot(step_index, label)
      screenshot_result = @browser.screenshot(@session.provider_session_id, full_page: false)
      @pending_screenshots << {
        data: screenshot_result[:data],
        filename: "task_#{task.id}_step_#{step_index}_#{label}.png"
      }
    rescue => e
      Rails.logger.warn "Failed to capture screenshot: #{e.message}"
    end

    # Queue cache entry for batch upsert later
    def queue_cache_entry(url:, action:, action_data:)
      @pending_cache_entries << {
        url: url,
        action: action,
        action_data: action_data
      }
    end

    # Flush all pending operations in batches
    def flush_pending_operations!
      flush_pending_screenshots!
      flush_pending_cache_entries!
      flush_steps_executed_count!
    end

    # Batch attach all pending screenshots
    def flush_pending_screenshots!
      return if @pending_screenshots.empty?

      attachments = @pending_screenshots.map do |screenshot|
        {
          io: StringIO.new(screenshot[:data]),
          filename: screenshot[:filename],
          content_type: "image/png"
        }
      end

      # Attach all screenshots in a single transaction
      ActiveRecord::Base.transaction do
        attachments.each do |attachment|
          task.screenshots.attach(attachment)
        end
      end

      @pending_screenshots.clear
    rescue => e
      Rails.logger.warn "Failed to flush screenshots: #{e.message}"
      @pending_screenshots.clear
    end

    # Batch upsert all pending cache entries
    def flush_pending_cache_entries!
      return if @pending_cache_entries.empty?

      ActionCacheEntry.batch_store(
        project: project,
        entries: @pending_cache_entries,
        instruction: task.instruction
      )

      @pending_cache_entries.clear
    rescue => e
      Rails.logger.warn "Failed to flush cache entries: #{e.message}"
      @pending_cache_entries.clear
    end

    # Update steps_executed count in a single DB call
    def flush_steps_executed_count!
      return if @steps_executed_count == 0

      task.update_columns(steps_executed: @steps_executed_count)
    rescue => e
      Rails.logger.warn "Failed to flush steps count: #{e.message}"
    end

    def extract_interactive_elements(html)
      # Parse HTML and find interactive elements
      doc = Nokogiri::HTML(html)
      elements = []

      # Extended selector list for better coverage
      selectors = [
        "a", "button", "input", "select", "textarea",
        "[role='button']", "[role='checkbox']", "[role='switch']", "[role='link']",
        "[onclick]", "[tabindex]", "[data-action]",
        "label[for]", ".checkbox", ".toggle", ".btn",
        "[class*='checkbox']", "[class*='toggle']", "[class*='button']"
      ].join(", ")

      doc.css(selectors).each_with_index do |el, idx|
        next if el["hidden"] || el["style"]&.include?("display: none")

        # Build descriptive text from various attributes
        text = el.text.strip.truncate(50)
        text = el["value"] if text.blank? && el["value"].present?
        text = el["aria-label"] if text.blank? && el["aria-label"].present?
        text = el["title"] if text.blank? && el["title"].present?
        text = el["placeholder"] if text.blank? && el["placeholder"].present?
        text = el["id"] if text.blank? && el["id"].present?
        text = el["class"]&.split&.first if text.blank? && el["class"].present?

        elements << {
          index: idx + 1,
          tag: el.name,
          type: el["type"],
          text: text,
          placeholder: el["placeholder"],
          aria_label: el["aria-label"],
          id: el["id"],
          name: el["name"],
          href: el["href"],
          class: el["class"]&.truncate(50),
          role: el["role"]
        }
      end

      elements.uniq { |e| [e[:tag], e[:text], e[:id]].compact.join("-") }
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

    # Clean the page of obstacles (cookie banners, popups, overlays)
    def clean_page!
      cleaner = PageCleaner.new(browser: @browser, session_id: @session.provider_session_id)
      result = cleaner.clean!

      if result[:actions_taken]&.any?
        Rails.logger.info "[TaskExecutor] Page cleaned: #{result[:actions_taken].join(', ')}"
      end
    rescue => e
      Rails.logger.warn "[TaskExecutor] Page cleaning failed: #{e.message}"
    end
  end
end
