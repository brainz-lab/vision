# frozen_string_literal: true

module BrowserProviders
  # Stagehand AI browser automation provider
  # https://stagehand.dev
  class Stagehand < Base
    API_BASE = "https://api.stagehand.dev/v1"

    def provider_name
      "stagehand"
    end

    def cloud?
      true
    end

    def create_session(**options)
      viewport = options[:viewport] || { width: 1280, height: 720 }

      log_action(:create_session, viewport: viewport)

      response = client.post("/sessions", {
        startUrl: options[:start_url],
        viewport: viewport,
        headless: options.fetch(:headless, true),
        modelName: options[:model] || "gpt-4o"
      }.compact)

      {
        session_id: response["sessionId"],
        provider: "stagehand"
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

    # Stagehand's primary AI action method
    # @param session_id [String] Session ID
    # @param instruction [String] Natural language action description
    # @param options [Hash] Action options
    # @return [Hash] Action result
    def act(session_id, instruction:, **options)
      log_action(:act, session_id: session_id, instruction: instruction.truncate(50))

      response = client.post("/sessions/#{session_id}/act", {
        action: instruction,
        modelName: options[:model],
        variables: options[:variables]
      }.compact)

      {
        success: response["success"] != false,
        action: response["action"],
        selector: response["selector"],
        element: response["element"],
        message: response["message"]
      }
    rescue HttpClient::RequestError => e
      log_error(:act, e)
      { success: false, error: e.message }
    end

    # Stagehand's observe method for page understanding
    # @param session_id [String] Session ID
    # @param instruction [String] What to observe
    # @return [Array<Hash>] Observed elements
    def observe(session_id, instruction:, **options)
      log_action(:observe, session_id: session_id, instruction: instruction.truncate(50))

      response = client.post("/sessions/#{session_id}/observe", {
        instruction: instruction,
        modelName: options[:model]
      }.compact)

      response["elements"] || []
    rescue HttpClient::RequestError => e
      log_error(:observe, e)
      []
    end

    # Stagehand's extract method for data extraction
    # @param session_id [String] Session ID
    # @param instruction [String] What to extract
    # @param schema [Hash] Optional JSON schema
    # @return [Hash] Extracted data
    def extract(session_id, instruction:, schema: nil, **options)
      log_action(:extract, session_id: session_id, instruction: instruction.truncate(50))

      response = client.post("/sessions/#{session_id}/extract", {
        instruction: instruction,
        schema: schema,
        modelName: options[:model]
      }.compact)

      response["data"]
    rescue HttpClient::RequestError => e
      log_error(:extract, e)
      raise
    end

    # Map standard perform_action to Stagehand's act
    def perform_action(session_id, action:, selector: nil, value: nil, **options)
      # Build instruction from action type
      instruction = case action.to_sym
      when :click
        "Click on #{selector}"
      when :type, :fill
        "Type '#{value}' into #{selector}"
      when :hover
        "Hover over #{selector}"
      when :scroll
        "Scroll #{value.to_i > 0 ? 'down' : 'up'} on the page"
      when :select
        "Select '#{value}' from #{selector}"
      when :wait
        sleep(value.to_f / 1000)
        return { success: true }
      else
        "#{action} on #{selector}"
      end

      act(session_id, instruction: instruction, **options)
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
