# frozen_string_literal: true

module LlmProviders
  # Google Gemini LLM provider
  # Supports Gemini 2.5-flash, 2.0-flash, 1.5-pro, and other Gemini models
  class Gemini < Base
    API_BASE = "https://generativelanguage.googleapis.com"

    # Map short model names to full API model IDs
    MODELS = {
      "gemini-2.5-flash" => "gemini-2.5-flash-preview-05-20",
      "gemini-2.0-flash" => "gemini-2.0-flash-exp",
      "gemini-1.5-pro" => "gemini-1.5-pro",
      "gemini-1.5-flash" => "gemini-1.5-flash"
    }.freeze

    def provider_name
      "gemini"
    end

    def complete(messages:, tools: nil, max_tokens: 4096)
      log_request(:complete, model: model, messages_count: messages.size)

      body = {
        contents: format_messages(messages),
        generationConfig: {
          maxOutputTokens: max_tokens
        }
      }

      # Extract system instruction if present
      system_msg = messages.find { |m| m[:role] == "system" }
      if system_msg
        body[:systemInstruction] = { parts: [ { text: system_msg[:content] } ] }
        body[:contents] = body[:contents].reject { |m| m[:role] == "system" }
      end

      body[:tools] = format_tools(tools) if tools.present?

      response = make_request("generateContent", body)
      result = parse_response(response)

      log_response(:complete, result)
      result
    rescue HttpClient::RequestError => e
      log_error(:complete, e)
      raise
    end

    def stream(messages:, tools: nil, &block)
      body = {
        contents: format_messages(messages),
        generationConfig: {
          maxOutputTokens: 4096
        }
      }

      body[:tools] = format_tools(tools) if tools.present?

      # Gemini uses different streaming endpoint
      client.post_stream("/v1beta/models/#{resolve_model}:streamGenerateContent?key=#{api_key}", body) do |chunk|
        parsed = parse_stream_chunk(chunk)
        yield parsed if parsed
      end
    end

    def analyze_image(image_data:, prompt:, format: :base64)
      log_request(:analyze_image, prompt_length: prompt.length)

      encoded_data = format == :base64 ? image_data : Base64.strict_encode64(image_data)

      body = {
        contents: [ {
          parts: [
            {
              inlineData: {
                mimeType: "image/png",
                data: encoded_data
              }
            },
            { text: prompt }
          ]
        } ]
      }

      response = make_request("generateContent", body)
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
        contents: format_messages(messages),
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: schema
        }
      }

      response = make_request("generateContent", body)
      text = response.dig("candidates", 0, "content", "parts", 0, "text")

      result = JSON.parse(text, symbolize_names: true)
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
          "Content-Type" => "application/json"
        },
        timeout: 120
      )
    end

    def resolve_model
      MODELS[model] || model
    end

    # Gemini uses query param for API key, not header
    def make_request(method, body)
      client.post(
        "/v1beta/models/#{resolve_model}:#{method}",
        body,
        params: { key: api_key }
      )
    end

    def format_messages(messages)
      messages.map do |msg|
        role = case msg[:role]
        when "assistant" then "model"
        when "system" then "user"  # System handled separately
        else msg[:role]
        end

        {
          role: role,
          parts: [ { text: msg[:content] } ]
        }
      end
    end

    def format_tools(tools)
      [ {
        functionDeclarations: tools.map do |tool|
          {
            name: tool[:name],
            description: tool[:description],
            parameters: tool[:schema] || tool[:parameters]
          }
        end
      } ]
    end

    def parse_response(response)
      candidate = response.dig("candidates", 0)
      content = candidate.dig("content", "parts", 0)

      # Check for function call
      if content["functionCall"]
        {
          text: nil,
          tool_calls: [ {
            name: content.dig("functionCall", "name"),
            input: content.dig("functionCall", "args")
          } ],
          stop_reason: candidate["finishReason"],
          usage: response["usageMetadata"]
        }
      else
        {
          text: content["text"],
          tool_calls: nil,
          stop_reason: candidate["finishReason"],
          usage: response["usageMetadata"]
        }
      end
    end

    def parse_stream_chunk(chunk)
      text = chunk.dig(:candidates, 0, :content, :parts, 0, :text)
      return nil unless text

      { type: :text, text: text }
    end
  end
end
