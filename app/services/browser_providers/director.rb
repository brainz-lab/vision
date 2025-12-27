# frozen_string_literal: true

module BrowserProviders
  # Director.ai browser automation provider
  # https://director.ai
  class Director < Base
    API_BASE = "https://api.director.ai/v1"

    def provider_name
      "director"
    end

    def cloud?
      true
    end

    def create_session(**options)
      viewport = options[:viewport] || { width: 1280, height: 720 }

      log_action(:create_session, viewport: viewport)

      response = client.post("/sessions", {
        viewport: viewport,
        headless: options.fetch(:headless, true),
        startUrl: options[:start_url]
      }.compact)

      {
        session_id: response["sessionId"],
        provider: "director"
      }
    rescue HttpClient::RequestError => e
      log_error(:create_session, e)
      raise
    end

    def close_session(session_id)
      log_action(:close_session, session_id: session_id)

      client.delete("/sessions/#{session_id}")
    rescue HttpClient::RequestError => e
      log_error(:close_session, e)
    end

    def navigate(session_id, url)
      log_action(:navigate, session_id: session_id, url: url)

      response = client.post("/sessions/#{session_id}/navigate", {
        url: url
      })

      {
        url: response["url"],
        title: response["title"]
      }
    rescue HttpClient::RequestError => e
      log_error(:navigate, e)
      { url: url, title: nil, error: e.message }
    end

    # Director's AI task execution
    # @param session_id [String] Session ID
    # @param task [String] Natural language task
    # @param options [Hash] Task options
    # @return [Hash] Task result
    def execute_task(session_id, task:, **options)
      log_action(:execute_task, session_id: session_id, task: task.truncate(50))

      response = client.post("/sessions/#{session_id}/task", {
        task: task,
        maxSteps: options[:max_steps] || 20,
        model: options[:model]
      }.compact)

      {
        task_id: response["taskId"],
        status: response["status"]
      }
    rescue HttpClient::RequestError => e
      log_error(:execute_task, e)
      { success: false, error: e.message }
    end

    # Get task status
    def get_task_status(session_id, task_id)
      response = client.get("/sessions/#{session_id}/task/#{task_id}")

      {
        status: response["status"],
        steps: response["steps"],
        result: response["result"],
        error: response["error"]
      }
    end

    def perform_action(session_id, action:, selector: nil, value: nil, **options)
      log_action(:perform_action, session_id: session_id, action: action)

      response = client.post("/sessions/#{session_id}/action", {
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

      response = client.post("/sessions/#{session_id}/screenshot", {
        fullPage: options.fetch(:full_page, true)
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
      response = client.get("/sessions/#{session_id}/content", params: { format: format })
      response["content"]
    end

    def current_url(session_id)
      response = client.get("/sessions/#{session_id}/state")
      response["url"]
    end

    def current_title(session_id)
      response = client.get("/sessions/#{session_id}/state")
      response["title"]
    end

    def evaluate(session_id, script)
      response = client.post("/sessions/#{session_id}/evaluate", {
        script: script
      })
      response["result"]
    end

    def wait_for_selector(session_id, selector, timeout: 30_000)
      client.post("/sessions/#{session_id}/wait", {
        selector: selector,
        timeout: timeout
      })
    end

    def wait_for_navigation(session_id, **options)
      client.post("/sessions/#{session_id}/wait-navigation", options)
    end

    def session_alive?(session_id)
      response = client.get("/sessions/#{session_id}")
      response["status"] == "active"
    rescue HttpClient::RequestError
      false
    end

    private

    def client
      @client ||= HttpClient.new(
        base_url: API_BASE,
        headers: {
          "Authorization" => "Bearer #{api_key}",
          "Content-Type" => "application/json"
        },
        timeout: 120
      )
    end
  end
end
