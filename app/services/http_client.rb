# frozen_string_literal: true

# Generic HTTP client wrapper with retries, timeouts, and JSON handling
# Used by all external provider integrations (LLM, cloud browsers)
class HttpClient
  class RequestError < StandardError
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end

  DEFAULT_TIMEOUT = 30
  DEFAULT_OPEN_TIMEOUT = 10
  MAX_RETRIES = 3
  RETRY_INTERVAL = 0.5
  RETRY_BACKOFF = 2

  attr_reader :base_url, :headers

  def initialize(base_url:, headers: {}, timeout: DEFAULT_TIMEOUT, open_timeout: DEFAULT_OPEN_TIMEOUT)
    @base_url = base_url
    @headers = headers
    @timeout = timeout
    @open_timeout = open_timeout
  end

  def get(path, params: {}, extra_headers: {})
    request(:get, path, params: params, extra_headers: extra_headers)
  end

  def post(path, body = nil, params: {}, extra_headers: {})
    request(:post, path, body: body, params: params, extra_headers: extra_headers)
  end

  def put(path, body = nil, params: {}, extra_headers: {})
    request(:put, path, body: body, params: params, extra_headers: extra_headers)
  end

  def delete(path, params: {}, extra_headers: {})
    request(:delete, path, params: params, extra_headers: extra_headers)
  end

  def post_stream(path, body = nil, extra_headers: {}, &block)
    request_stream(:post, path, body: body, extra_headers: extra_headers, &block)
  end

  private

  def connection
    @connection ||= Faraday.new(url: base_url) do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.request :retry, {
        max: MAX_RETRIES,
        interval: RETRY_INTERVAL,
        backoff_factor: RETRY_BACKOFF,
        retry_statuses: [ 429, 500, 502, 503, 504 ],
        methods: [ :get, :post, :put, :delete ]
      }
      conn.options.timeout = @timeout
      conn.options.open_timeout = @open_timeout
      conn.adapter Faraday.default_adapter
    end
  end

  def request(method, path, body: nil, params: {}, extra_headers: {})
    response = connection.send(method) do |req|
      req.url path
      req.params = params if params.any?
      req.headers = headers.merge(extra_headers)
      req.body = body if body
    end

    handle_response(response)
  rescue Faraday::TimeoutError => e
    raise RequestError.new("Request timed out: #{e.message}")
  rescue Faraday::ConnectionFailed => e
    raise RequestError.new("Connection failed: #{e.message}")
  end

  def request_stream(method, path, body: nil, extra_headers: {})
    uri = URI.parse("#{base_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = 300 # 5 minutes for streaming

    request = Net::HTTP::Post.new(uri.path)
    headers.merge(extra_headers).each { |k, v| request[k] = v }
    request["Content-Type"] = "application/json"
    request["Accept"] = "text/event-stream"
    request.body = body.to_json if body

    http.request(request) do |response|
      unless response.is_a?(Net::HTTPSuccess)
        raise RequestError.new(
          "HTTP #{response.code}: #{response.message}",
          status: response.code.to_i,
          body: response.body
        )
      end

      response.read_body do |chunk|
        # Parse SSE events
        chunk.split("\n\n").each do |event|
          next if event.strip.empty?

          data_line = event.lines.find { |l| l.start_with?("data:") }
          next unless data_line

          data = data_line.sub("data:", "").strip
          next if data == "[DONE]"

          begin
            parsed = JSON.parse(data, symbolize_names: true)
            yield parsed
          rescue JSON::ParserError
            # Skip unparseable chunks
          end
        end
      end
    end
  end

  def handle_response(response)
    case response.status
    when 200..299
      response.body
    when 400
      raise RequestError.new("Bad request: #{error_message(response)}", status: 400, body: response.body)
    when 401
      raise RequestError.new("Unauthorized: Invalid API key", status: 401, body: response.body)
    when 403
      raise RequestError.new("Forbidden: Access denied", status: 403, body: response.body)
    when 404
      raise RequestError.new("Not found: #{error_message(response)}", status: 404, body: response.body)
    when 429
      raise RequestError.new("Rate limited: Too many requests", status: 429, body: response.body)
    when 500..599
      raise RequestError.new("Server error: #{error_message(response)}", status: response.status, body: response.body)
    else
      raise RequestError.new("Unexpected response: #{response.status}", status: response.status, body: response.body)
    end
  end

  def error_message(response)
    return response.body["error"]["message"] if response.body.is_a?(Hash) && response.body.dig("error", "message")
    return response.body["error"] if response.body.is_a?(Hash) && response.body["error"]
    return response.body["message"] if response.body.is_a?(Hash) && response.body["message"]

    response.body.to_s.truncate(200)
  end
end
