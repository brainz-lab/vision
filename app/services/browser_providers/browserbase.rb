# frozen_string_literal: true

module BrowserProviders
  # Browserbase cloud browser provider
  # https://browserbase.com
  class Browserbase < Base
    API_BASE = "https://www.browserbase.com/v1"

    def provider_name
      "browserbase"
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

      response = client.post("/sessions", {
        projectId: project_id,
        browserSettings: {
          viewport: viewport,
          fingerprint: options[:fingerprint]
        }.compact,
        proxies: options[:proxies],
        timeout: options[:timeout_minutes] ? options[:timeout_minutes] * 60 * 1000 : nil
      }.compact)

      {
        session_id: response["id"],
        provider: "browserbase",
        connect_url: response["connectUrl"],
        debug_url: response["debuggerFullscreenUrl"]
      }
    rescue HttpClient::RequestError => e
      log_error(:create_session, e)
      raise
    end

    def close_session(session_id)
      log_action(:close_session, session_id: session_id)

      client.post("/sessions/#{session_id}/stop")
    rescue HttpClient::RequestError => e
      log_error(:close_session, e)
    end

    # Browserbase uses CDP connection - we connect via Playwright
    def get_playwright_connection(session_id)
      session_info = client.get("/sessions/#{session_id}")
      connect_url = session_info["connectUrl"]

      # Create Playwright connection
      playwright = Playwright.create(playwright_cli_executable_path: find_playwright_path)
      browser = playwright.chromium.connect_over_cdp(connect_url)

      {
        playwright: playwright,
        browser: browser,
        page: browser.contexts.first&.pages&.first || browser.new_page
      }
    end

    def navigate(session_id, url)
      log_action(:navigate, session_id: session_id, url: url)

      connection = get_or_create_connection(session_id)
      page = connection[:page]

      page.goto(url, wait_until: "networkidle")

      {
        url: page.url,
        title: page.title
      }
    rescue => e
      log_error(:navigate, e)
      { url: url, title: nil, error: e.message }
    end

    def perform_action(session_id, action:, selector: nil, value: nil, **options)
      log_action(:perform_action, session_id: session_id, action: action)

      connection = get_or_create_connection(session_id)
      page = connection[:page]

      case action.to_sym
      when :click
        page.click(selector, **options.slice(:timeout, :button))
      when :type
        page.type(selector, value.to_s, **options.slice(:timeout, :delay))
      when :fill
        page.fill(selector, value.to_s)
      when :hover
        page.hover(selector)
      when :scroll
        page.evaluate("window.scrollBy(0, #{value.to_i})")
      when :select
        page.select_option(selector, value)
      when :wait
        sleep(value.to_f / 1000)
      when :press
        page.keyboard.press(value.to_s)
      end

      { success: true, url: page.url }
    rescue => e
      log_error(:perform_action, e)
      { success: false, error: e.message }
    end

    def screenshot(session_id, **options)
      log_action(:screenshot, session_id: session_id)

      connection = get_or_create_connection(session_id)
      page = connection[:page]

      data = page.screenshot(
        full_page: options.fetch(:full_page, true),
        type: "png"
      )

      {
        data: data,
        content_type: "image/png"
      }
    rescue => e
      log_error(:screenshot, e)
      raise
    end

    def page_content(session_id, format: :html)
      connection = get_or_create_connection(session_id)
      page = connection[:page]

      case format
      when :html
        page.content
      when :text
        page.evaluate("document.body.innerText")
      when :accessibility
        page.accessibility.snapshot
      end
    end

    def current_url(session_id)
      connection = get_or_create_connection(session_id)
      connection[:page].url
    end

    def current_title(session_id)
      connection = get_or_create_connection(session_id)
      connection[:page].title
    end

    def evaluate(session_id, script)
      connection = get_or_create_connection(session_id)
      connection[:page].evaluate(script)
    end

    def wait_for_selector(session_id, selector, timeout: 30_000)
      connection = get_or_create_connection(session_id)
      connection[:page].wait_for_selector(selector, timeout: timeout)
    end

    def wait_for_navigation(session_id, **options)
      connection = get_or_create_connection(session_id)
      connection[:page].wait_for_navigation(**options)
    end

    def session_alive?(session_id)
      response = client.get("/sessions/#{session_id}")
      response["status"] == "RUNNING"
    rescue HttpClient::RequestError
      false
    end

    # Get session recording
    def get_recording(session_id)
      response = client.get("/sessions/#{session_id}/recording")
      response["url"]
    end

    # Get session logs
    def get_logs(session_id)
      client.get("/sessions/#{session_id}/logs")
    end

    private

    def client
      @client ||= HttpClient.new(
        base_url: API_BASE,
        headers: {
          "Authorization" => "Bearer #{api_key}",
          "Content-Type" => "application/json"
        },
        timeout: 60
      )
    end

    def project_id
      credentials[:project_id] || ENV["BROWSERBASE_PROJECT_ID"]
    end

    # Cache Playwright connections
    def get_or_create_connection(session_id)
      @connections ||= {}
      @connections[session_id] ||= get_playwright_connection(session_id)
    end

    def find_playwright_path
      paths = [
        "npx playwright",
        "/usr/local/bin/npx playwright",
        File.join(ENV["HOME"], ".npm-global/bin/npx playwright")
      ]

      paths.find { |path| system("which #{path.split.first} > /dev/null 2>&1") } || "npx playwright"
    end
  end
end
