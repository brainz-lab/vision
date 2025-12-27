# frozen_string_literal: true

module Ai
  # Single AI-powered action executor
  # Implements page.ai() functionality - analyze page and perform action
  class ActionExecutor
    attr_reader :browser, :session_id, :llm, :project

    def initialize(browser:, session_id:, llm:, project: nil)
      @browser = browser
      @session_id = session_id
      @llm = llm
      @project = project
    end

    # Execute a single AI-powered action
    # @param instruction [String] Natural language instruction
    # @param use_overlay [Boolean] Whether to add element overlays
    # @return [Hash] Action result
    def execute(instruction, use_overlay: true)
      # Capture current state with overlays
      if use_overlay
        overlay_data = ElementOverlay.capture_with_overlays(@browser, @session_id)
        screenshot = overlay_data[:screenshot]
        elements = overlay_data[:elements]
      else
        screenshot_result = @browser.screenshot(@session_id, full_page: false)
        screenshot = screenshot_result[:data]
        elements = extract_elements_from_html
      end

      url = @browser.current_url(@session_id)
      title = @browser.current_title(@session_id)

      # Build prompt for LLM
      prompt = build_prompt(instruction, url, title, elements)

      # Get LLM decision
      response = @llm.analyze_image(
        image_data: screenshot,
        prompt: prompt,
        format: :binary
      )

      # Parse the action
      decision = parse_decision(response[:text])

      # Execute the action
      if decision[:complete]
        # No action needed, instruction already satisfied
        {
          success: true,
          complete: true,
          reasoning: decision[:reasoning],
          url: url
        }
      elsif decision[:action]
        execute_action(decision, elements, url)
      else
        {
          success: false,
          error: "Could not determine action to take",
          reasoning: decision[:reasoning]
        }
      end
    rescue => e
      Rails.logger.error "ActionExecutor error: #{e.message}"
      { success: false, error: e.message }
    end

    private

    def build_prompt(instruction, url, title, elements)
      element_list = if elements.is_a?(Array)
        ElementOverlay.format_for_prompt(elements)
      else
        elements.to_s
      end

      <<~PROMPT
        You are a browser automation assistant. Execute this instruction:
        #{instruction}

        Current page: #{url}
        Title: #{title}

        Interactive elements on page (with numbered overlays):
        #{element_list}

        Analyze the screenshot and determine the action to take.

        Respond with JSON only:
        {
          "thinking": "your reasoning about what to do",
          "action": {
            "type": "click|type|fill|scroll|hover|select|wait|press|navigate",
            "element_index": 5,
            "selector": "CSS selector (optional, use if element_index not available)",
            "value": "value for type/fill/navigate/press actions"
          },
          "complete": false
        }

        If the instruction is already satisfied (e.g., "check if logged in" and user is logged in):
        {
          "thinking": "The page shows...",
          "action": null,
          "complete": true,
          "result": "description of current state"
        }

        Action types:
        - click: Click element by index or selector
        - type/fill: Enter text into input field
        - scroll: Scroll the page (value: "down", "up", "page_down", "page_up", "bottom", "top", or pixel amount)
        - scroll_into_view: Scroll element into view (requires element_index or selector)
        - hover: Hover over element
        - select: Select option from dropdown (value: option text)
        - wait: Wait for something (value: milliseconds)
        - press: Press keyboard key (value: key name like "Enter", "Tab")
        - navigate: Go to URL (value: full URL)

        Scroll efficiently: use "page_down" to scroll full pages, "bottom" to jump to end.
      PROMPT
    end

    def parse_decision(text)
      json_match = text.match(/\{[\s\S]*\}/)
      return { reasoning: "Failed to parse response" } unless json_match

      data = JSON.parse(json_match[0], symbolize_names: true)

      {
        reasoning: data[:thinking],
        action: data[:action]&.symbolize_keys,
        complete: data[:complete] == true,
        result: data[:result]
      }
    rescue JSON::ParserError => e
      Rails.logger.warn "Failed to parse LLM response: #{e.message}"
      { reasoning: "JSON parse error" }
    end

    def execute_action(decision, elements, url_before)
      action = decision[:action]
      action_type = action[:type].to_sym

      case action_type
      when :navigate
        result = @browser.navigate(@session_id, action[:value])
        {
          success: result[:url].present?,
          action: "navigate",
          value: action[:value],
          url: result[:url],
          reasoning: decision[:reasoning]
        }

      when :click
        target = resolve_target(action, elements)
        result = @browser.perform_action(
          @session_id,
          action: :click,
          selector: target[:selector],
          **target[:coordinates]
        )
        wait_for_navigation_if_needed
        {
          success: result[:success] != false,
          action: "click",
          selector: target[:selector],
          url: @browser.current_url(@session_id),
          reasoning: decision[:reasoning],
          error: result[:error]
        }

      when :type, :fill
        target = resolve_target(action, elements)
        result = @browser.perform_action(
          @session_id,
          action: :fill,
          selector: target[:selector],
          value: action[:value],
          **target[:coordinates]
        )
        {
          success: result[:success] != false,
          action: action_type.to_s,
          selector: target[:selector],
          value: action[:value],
          url: @browser.current_url(@session_id),
          reasoning: decision[:reasoning],
          error: result[:error]
        }

      when :scroll
        scroll_value = action[:value] || "page_down"
        result = @browser.perform_action(
          @session_id,
          action: :scroll,
          value: scroll_value
        )
        {
          success: true,
          action: "scroll",
          value: scroll_value,
          url: @browser.current_url(@session_id),
          reasoning: decision[:reasoning]
        }

      when :scroll_into_view
        target = resolve_target(action, elements)
        result = @browser.perform_action(
          @session_id,
          action: :scroll_into_view,
          selector: target[:selector]
        )
        {
          success: result[:success] != false,
          action: "scroll_into_view",
          selector: target[:selector],
          url: @browser.current_url(@session_id),
          reasoning: decision[:reasoning]
        }

      when :hover
        target = resolve_target(action, elements)
        result = @browser.perform_action(
          @session_id,
          action: :hover,
          selector: target[:selector],
          **target[:coordinates]
        )
        {
          success: result[:success] != false,
          action: "hover",
          selector: target[:selector],
          url: @browser.current_url(@session_id),
          reasoning: decision[:reasoning]
        }

      when :select
        target = resolve_target(action, elements)
        result = @browser.perform_action(
          @session_id,
          action: :select,
          selector: target[:selector],
          value: action[:value]
        )
        {
          success: result[:success] != false,
          action: "select",
          selector: target[:selector],
          value: action[:value],
          url: @browser.current_url(@session_id),
          reasoning: decision[:reasoning]
        }

      when :wait
        sleep(action[:value].to_i / 1000.0)
        {
          success: true,
          action: "wait",
          value: action[:value],
          url: @browser.current_url(@session_id),
          reasoning: decision[:reasoning]
        }

      when :press
        result = @browser.perform_action(
          @session_id,
          action: :press,
          value: action[:value]
        )
        wait_for_navigation_if_needed if %w[Enter Return].include?(action[:value])
        {
          success: result[:success] != false,
          action: "press",
          value: action[:value],
          url: @browser.current_url(@session_id),
          reasoning: decision[:reasoning]
        }

      else
        {
          success: false,
          error: "Unknown action type: #{action_type}",
          reasoning: decision[:reasoning]
        }
      end
    end

    def resolve_target(action, elements)
      # Prefer element index if available
      if action[:element_index].present? && elements.is_a?(Array)
        element = elements.find { |e| e[:index] == action[:element_index] }

        if element
          selector = ElementOverlay.selector_for_index(elements, action[:element_index])

          return {
            selector: selector,
            coordinates: element[:rect] ? {
              x: element[:rect][:x] + (element[:rect][:width] / 2),
              y: element[:rect][:y] + (element[:rect][:height] / 2)
            } : {}
          }
        end
      end

      # Fall back to selector
      {
        selector: action[:selector],
        coordinates: {}
      }
    end

    def wait_for_navigation_if_needed
      sleep(0.5) # Brief wait for potential navigation
    rescue
      # Ignore errors
    end

    def extract_elements_from_html
      html = @browser.page_content(@session_id, format: :html)
      doc = Nokogiri::HTML(html)
      elements = []

      selectors = "a, button, input, select, textarea, [role='button'], [onclick]"
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
          name: el["name"]
        }
      end

      elements
    rescue => e
      Rails.logger.warn "Failed to extract elements: #{e.message}"
      []
    end
  end
end
