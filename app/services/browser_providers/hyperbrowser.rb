# frozen_string_literal: true

module BrowserProviders
  # Hyperbrowser cloud browser provider
  # Supports Browser-Use and Claude Computer Use agents
  # https://hyperbrowser.ai
  class Hyperbrowser < Base
    API_BASE = "https://api.hyperbrowser.ai"

    def provider_name
      "hyperbrowser"
    end

    def cloud?
      true
    end

    def supports_cdp?
      true
    end

    def create_session(**options)
      viewport = options[:viewport] || { width: 1280, height: 720 }

      log_action(:create_session, viewport: viewport)

      response = client.post("/api/v1/sessions", {
        viewport: viewport,
        headless: options.fetch(:headless, true),
        proxy: options[:proxy],
        stealth: options[:stealth],
        solveCaptchas: options[:solve_captchas]
      }.compact)

      {
        session_id: response["id"],
        provider: "hyperbrowser",
        websocket_url: response["wsEndpoint"],
        connect_url: response["connectUrl"],
        live_url: response["liveUrl"]
      }
    rescue HttpClient::RequestError => e
      log_error(:create_session, e)
      raise
    end

    def close_session(session_id)
      log_action(:close_session, session_id: session_id)

      client.post("/api/v1/sessions/#{session_id}/stop")
    rescue HttpClient::RequestError => e
      log_error(:close_session, e)
      # Don't raise - session might already be closed
    end

    def navigate(session_id, url)
      log_action(:navigate, session_id: session_id, url: url)

      response = client.post("/api/v1/sessions/#{session_id}/navigate", {
        url: url,
        waitUntil: "networkidle"
      })

      {
        url: response["url"],
        title: response["title"]
      }
    rescue HttpClient::RequestError => e
      log_error(:navigate, e)
      { url: url, title: nil, error: e.message }
    end

    def perform_action(session_id, action:, selector: nil, value: nil, **options)
      log_action(:perform_action, session_id: session_id, action: action, selector: selector)

      response = client.post("/api/v1/sessions/#{session_id}/action", {
        action: action,
        selector: selector,
        value: value,
        options: options
      }.compact)

      {
        success: response["success"] != false,
        url: response["url"],
        error: response["error"]
      }
    rescue HttpClient::RequestError => e
      log_error(:perform_action, e)
      { success: false, error: e.message }
    end

    def screenshot(session_id, **options)
      log_action(:screenshot, session_id: session_id)

      response = client.post("/api/v1/sessions/#{session_id}/screenshot", {
        fullPage: options.fetch(:full_page, true),
        type: "png"
      })

      {
        data: Base64.decode64(response["data"]),
        content_type: "image/png"
      }
    rescue HttpClient::RequestError => e
      log_error(:screenshot, e)
      raise
    end

    def page_content(session_id, format: :html)
      log_action(:page_content, session_id: session_id, format: format)

      response = client.get("/api/v1/sessions/#{session_id}/content", params: { format: format })
      response["content"]
    rescue HttpClient::RequestError => e
      log_error(:page_content, e)
      raise
    end

    def current_url(session_id)
      response = client.get("/api/v1/sessions/#{session_id}/state")
      response["url"]
    end

    def current_title(session_id)
      response = client.get("/api/v1/sessions/#{session_id}/state")
      response["title"]
    end

    def evaluate(session_id, script)
      log_action(:evaluate, session_id: session_id)

      response = client.post("/api/v1/sessions/#{session_id}/evaluate", {
        script: script
      })

      response["result"]
    rescue HttpClient::RequestError => e
      log_error(:evaluate, e)
      raise
    end

    def wait_for_selector(session_id, selector, timeout: 30_000)
      log_action(:wait_for_selector, session_id: session_id, selector: selector)

      client.post("/api/v1/sessions/#{session_id}/wait", {
        selector: selector,
        timeout: timeout
      })
    rescue HttpClient::RequestError => e
      log_error(:wait_for_selector, e)
      raise
    end

    def wait_for_navigation(session_id, **options)
      log_action(:wait_for_navigation, session_id: session_id)

      client.post("/api/v1/sessions/#{session_id}/wait-navigation", options)
    rescue HttpClient::RequestError => e
      log_error(:wait_for_navigation, e)
      raise
    end

    def session_alive?(session_id)
      response = client.get("/api/v1/sessions/#{session_id}/health")
      response["alive"] == true
    rescue HttpClient::RequestError
      false
    end

    # ============================================
    # Hyperbrowser-specific AI Agent Methods
    # ============================================

    # Execute a Browser-Use task
    # @param task [String] Natural language task description
    # @param options [Hash] Task options (model, max_steps, etc.)
    # @return [Hash] Task result
    def browser_use_task(task:, session_id: nil, **options)
      log_action(:browser_use_task, task: task.truncate(50))

      body = {
        task: task,
        llm: options[:model] || "gemini-2.5-flash",
        maxSteps: options[:max_steps] || 20,
        useVision: options.fetch(:use_vision, true),
        sessionId: session_id,
        keepBrowserOpen: options[:keep_browser_open]
      }.compact

      # Add custom API keys if provided
      if options[:use_custom_api_keys] && options[:api_keys]
        body[:useCustomApiKeys] = true
        body[:apiKeys] = options[:api_keys]
      end

      response = client.post("/api/task/browser-use", body)

      {
        job_id: response["jobId"],
        live_url: response["liveUrl"],
        status: "started"
      }
    end

    # Execute a Claude Computer Use task
    # @param task [String] Natural language task description
    # @param options [Hash] Task options
    # @return [Hash] Task result
    def claude_computer_use_task(task:, session_id: nil, **options)
      log_action(:claude_computer_use_task, task: task.truncate(50))

      body = {
        task: task,
        llm: options[:model] || "claude-sonnet-4-5",
        maxSteps: options[:max_steps] || 20,
        sessionId: session_id,
        keepBrowserOpen: options[:keep_browser_open],
        useComputerAction: options[:use_computer_action]
      }.compact

      if options[:use_custom_api_keys] && options[:api_keys]
        body[:useCustomApiKeys] = true
        body[:apiKeys] = options[:api_keys]
      end

      response = client.post("/api/task/claude-computer-use", body)

      {
        job_id: response["jobId"],
        live_url: response["liveUrl"],
        status: "started"
      }
    end

    # Poll for task status
    # @param job_id [String] Job ID
    # @param task_type [String] "browser-use" or "claude-computer-use"
    # @return [Hash] Task status
    def get_task_status(job_id, task_type: "browser-use")
      response = client.get("/api/task/#{task_type}/#{job_id}/status")

      {
        status: response["status"],
        steps: response["steps"],
        current_step: response["currentStep"]
      }
    end

    # Get full task result
    # @param job_id [String] Job ID
    # @param task_type [String] "browser-use" or "claude-computer-use"
    # @return [Hash] Full task result
    def get_task_result(job_id, task_type: "browser-use")
      response = client.get("/api/task/#{task_type}/#{job_id}")

      {
        status: response["status"],
        final_result: response.dig("data", "finalResult"),
        steps: response.dig("data", "steps"),
        error: response["error"]
      }
    end

    # Stop a running task
    # @param job_id [String] Job ID
    # @param task_type [String] "browser-use" or "claude-computer-use"
    def stop_task(job_id, task_type: "browser-use")
      client.put("/api/task/#{task_type}/#{job_id}/stop")
    end

    # Execute task and wait for completion (blocking)
    # @param task [String] Task description
    # @param task_type [String] "browser-use" or "claude-computer-use"
    # @param options [Hash] Task options
    # @return [Hash] Task result
    def execute_task_and_wait(task:, task_type: "browser-use", poll_interval: 5, timeout: 300, **options)
      start_time = Time.current

      # Start the task
      result = if task_type == "claude-computer-use"
        claude_computer_use_task(task: task, **options)
      else
        browser_use_task(task: task, **options)
      end

      job_id = result[:job_id]

      # Poll for completion
      loop do
        elapsed = Time.current - start_time
        raise "Task timeout after #{timeout}s" if elapsed > timeout

        status = get_task_status(job_id, task_type: task_type)

        case status[:status]
        when "completed", "failed"
          return get_task_result(job_id, task_type: task_type)
        else
          sleep(poll_interval)
        end
      end
    end

    private

    def client
      @client ||= HttpClient.new(
        base_url: API_BASE,
        headers: {
          "x-api-key" => api_key,
          "Content-Type" => "application/json"
        },
        timeout: 120
      )
    end
  end
end
