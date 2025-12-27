# frozen_string_literal: true

module LlmProviders
  # OpenAI GPT LLM provider
  # Supports GPT-4o, GPT-4o-mini, GPT-4-turbo, and other OpenAI models
  class Openai < Base
    API_BASE = "https://api.openai.com"

    # Map short model names to full API model IDs
    MODELS = {
      "gpt-4o" => "gpt-4o",
      "gpt-4o-mini" => "gpt-4o-mini",
      "gpt-4-turbo" => "gpt-4-turbo",
      "gpt-4" => "gpt-4"
    }.freeze

    def provider_name
      "openai"
    end

    def complete(messages:, tools: nil, max_tokens: 4096)
      log_request(:complete, model: model, messages_count: messages.size)

      body = {
        model: resolve_model,
        max_tokens: max_tokens,
        messages: format_messages(messages)
      }

      body[:tools] = format_tools(tools) if tools.present?

      response = client.post("/v1/chat/completions", body)
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

      body[:tools] = format_tools(tools) if tools.present?

      client.post_stream("/v1/chat/completions", body) do |chunk|
        parsed = parse_stream_chunk(chunk)
        yield parsed if parsed
      end
    end

    def analyze_image(image_data:, prompt:, format: :base64)
      log_request(:analyze_image, prompt_length: prompt.length)

      encoded_data = format == :base64 ? image_data : Base64.strict_encode64(image_data)
      data_url = "data:image/png;base64,#{encoded_data}"

      messages = [{
        role: "user",
        content: [
          { type: "image_url", image_url: { url: data_url } },
          { type: "text", text: prompt }
        ]
      }]

      body = {
        model: resolve_model,
        max_tokens: 4096,
        messages: messages
      }

      response = client.post("/v1/chat/completions", body)
      result = parse_response(response)

      log_response(:analyze_image, text_length: result[:text]&.length)
      result
    rescue HttpClient::RequestError => e
      log_error(:analyze_image, e)
      raise
    end

    def extract_structured(messages:, schema:)
      log_request(:extract_structured, schema_name: schema[:title] || "unnamed")

      body = {
        model: resolve_model,
        messages: format_messages(messages),
        response_format: {
          type: "json_schema",
          json_schema: {
            name: schema[:title] || "extraction",
            schema: schema,
            strict: true
          }
        }
      }

      response = client.post("/v1/chat/completions", body)
      content = response.dig("choices", 0, "message", "content")

      result = JSON.parse(content, symbolize_names: true)
      log_response(:extract_structured, result: result)
      result
    rescue JSON::ParserError => e
      log_error(:extract_structured, e)
      raise HttpClient::RequestError.new("Failed to parse structured output: #{e.message}")
    rescue HttpClient::RequestError => e
      log_error(:extract_structured, e)
      raise
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

    def resolve_model
      MODELS[model] || model
    end

    def format_messages(messages)
      messages.map do |msg|
        formatted = { role: msg[:role], content: msg[:content] }

        # Handle tool results
        if msg[:role] == "tool"
          formatted[:tool_call_id] = msg[:tool_call_id]
        end

        formatted
      end
    end

    def format_tools(tools)
      tools.map do |tool|
        {
          type: "function",
          function: {
            name: tool[:name],
            description: tool[:description],
            parameters: tool[:schema] || tool[:parameters]
          }
        }
      end
    end

    def parse_response(response)
      choice = response.dig("choices", 0)
      message = choice["message"]

      {
        text: message["content"],
        tool_calls: message["tool_calls"]&.map do |tc|
          {
            name: tc.dig("function", "name"),
            input: JSON.parse(tc.dig("function", "arguments"), symbolize_names: true),
            id: tc["id"]
          }
        end,
        stop_reason: choice["finish_reason"],
        usage: response["usage"]
      }
    rescue JSON::ParserError
      {
        text: message["content"],
        tool_calls: nil,
        stop_reason: choice["finish_reason"],
        usage: response["usage"]
      }
    end

    def parse_stream_chunk(chunk)
      delta = chunk.dig(:choices, 0, :delta)
      return nil unless delta

      if delta[:content]
        { type: :text, text: delta[:content] }
      elsif delta[:tool_calls]
        { type: :tool_call, data: delta[:tool_calls] }
      end
    end
  end
end
