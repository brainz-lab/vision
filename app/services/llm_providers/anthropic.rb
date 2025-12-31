# frozen_string_literal: true

module LlmProviders
  # Anthropic Claude LLM provider
  # Supports Claude Sonnet 4, Opus 4, and other Claude models
  class Anthropic < Base
    API_BASE = "https://api.anthropic.com"
    API_VERSION = "2023-06-01"

    # Map short model names to full API model IDs
    MODELS = {
      "claude-sonnet-4" => "claude-sonnet-4-20250514",
      "claude-opus-4" => "claude-opus-4-20250514",
      "claude-3-5-sonnet" => "claude-3-5-sonnet-20241022"
    }.freeze

    def provider_name
      "anthropic"
    end

    def complete(messages:, tools: nil, max_tokens: 4096)
      log_request(:complete, model: model, messages_count: messages.size)

      body = {
        model: resolve_model,
        max_tokens: max_tokens,
        messages: format_messages(messages)
      }

      # Add system message if present
      system_msg = messages.find { |m| m[:role] == "system" }
      if system_msg
        body[:system] = system_msg[:content]
        body[:messages] = body[:messages].reject { |m| m[:role] == "system" }
      end

      # Add tools if provided
      body[:tools] = format_tools(tools) if tools.present?

      response = client.post("/v1/messages", body)
      result = parse_response(response)

      log_response(:complete, result)
      result
    rescue HttpClient::RequestError => e
      log_error(:complete, e)
      raise
    end

    def stream(messages:, tools: nil, &block)
      body = {
        model: resolve_model,
        max_tokens: 4096,
        messages: format_messages(messages),
        stream: true
      }

      # Add system message if present
      system_msg = messages.find { |m| m[:role] == "system" }
      if system_msg
        body[:system] = system_msg[:content]
        body[:messages] = body[:messages].reject { |m| m[:role] == "system" }
      end

      body[:tools] = format_tools(tools) if tools.present?

      client.post_stream("/v1/messages", body) do |chunk|
        parsed = parse_stream_chunk(chunk)
        yield parsed if parsed
      end
    end

    def analyze_image(image_data:, prompt:, format: :base64)
      log_request(:analyze_image, prompt_length: prompt.length)

      encoded_data = format == :base64 ? image_data : Base64.strict_encode64(image_data)

      messages = [ {
        role: "user",
        content: [
          {
            type: "image",
            source: {
              type: "base64",
              media_type: "image/png",
              data: encoded_data
            }
          },
          {
            type: "text",
            text: prompt
          }
        ]
      } ]

      body = {
        model: resolve_model,
        max_tokens: 4096,
        messages: messages
      }

      response = client.post("/v1/messages", body)
      result = parse_response(response)

      log_response(:analyze_image, text_length: result[:text]&.length)
      result
    rescue HttpClient::RequestError => e
      log_error(:analyze_image, e)
      raise
    end

    def extract_structured(messages:, schema:)
      log_request(:extract_structured, schema_name: schema[:title] || "unnamed")

      # Use tool_use for structured output
      tools = [ {
        name: "extract_data",
        description: "Extract structured data from the content",
        input_schema: schema
      } ]

      body = {
        model: resolve_model,
        max_tokens: 4096,
        messages: format_messages(messages),
        tools: tools,
        tool_choice: { type: "tool", name: "extract_data" }
      }

      response = client.post("/v1/messages", body)
      result = parse_tool_response(response)

      log_response(:extract_structured, result: result)
      result
    rescue HttpClient::RequestError => e
      log_error(:extract_structured, e)
      raise
    end

    # Anthropic Computer Use specific method
    # @param messages [Array<Hash>] Messages with computer use context
    # @param tools [Array<Hash>] Computer use tools
    def computer_use(messages:, tools:)
      body = {
        model: resolve_model,
        max_tokens: 4096,
        messages: format_messages(messages),
        tools: tools
      }

      response = client.post(
        "/v1/messages",
        body,
        extra_headers: { "anthropic-beta" => "computer-use-2024-10-22" }
      )
      parse_response(response)
    end

    private

    def client
      @client ||= HttpClient.new(
        base_url: API_BASE,
        headers: {
          "x-api-key" => api_key,
          "anthropic-version" => API_VERSION,
          "Content-Type" => "application/json"
        },
        timeout: 120 # Claude can take a while for complex requests
      )
    end

    def resolve_model
      MODELS[model] || model
    end

    def format_tools(tools)
      tools.map do |tool|
        {
          name: tool[:name],
          description: tool[:description],
          input_schema: tool[:schema] || tool[:input_schema]
        }
      end
    end

    def parse_response(response)
      content = response["content"] || []

      {
        text: content.find { |c| c["type"] == "text" }&.dig("text"),
        tool_calls: content.select { |c| c["type"] == "tool_use" }.map do |t|
          { name: t["name"], input: t["input"], id: t["id"] }
        end,
        stop_reason: response["stop_reason"],
        usage: response["usage"]
      }
    end

    def parse_tool_response(response)
      content = response["content"] || []
      tool_use = content.find { |c| c["type"] == "tool_use" }
      tool_use&.dig("input")
    end

    def parse_stream_chunk(chunk)
      return nil unless chunk[:type] == "content_block_delta"

      delta = chunk[:delta]
      return nil unless delta

      case delta[:type]
      when "text_delta"
        { type: :text, text: delta[:text] }
      when "input_json_delta"
        { type: :tool_input, partial_json: delta[:partial_json] }
      end
    end
  end
end
