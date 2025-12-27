# frozen_string_literal: true

module LlmProviders
  # Abstract base class for LLM providers
  # All providers must implement the core interface methods
  class Base
    attr_reader :model, :config

    def initialize(model:, config: {})
      @model = model
      @config = config
    end

    # Generate a chat completion
    # @param messages [Array<Hash>] Array of {role:, content:} messages
    # @param tools [Array<Hash>, nil] Optional tool definitions
    # @param max_tokens [Integer] Maximum tokens to generate
    # @return [Hash] {text:, tool_calls:, stop_reason:, usage:}
    def complete(messages:, tools: nil, max_tokens: 4096)
      raise NotImplementedError, "#{self.class} must implement #complete"
    end

    # Stream a chat completion
    # @param messages [Array<Hash>] Array of {role:, content:} messages
    # @param tools [Array<Hash>, nil] Optional tool definitions
    # @yield [Hash] Partial response chunks
    def stream(messages:, tools: nil, &block)
      raise NotImplementedError, "#{self.class} must implement #stream"
    end

    # Analyze an image with vision capabilities
    # @param image_data [String] Base64 encoded image or binary data
    # @param prompt [String] Text prompt for analysis
    # @param format [Symbol] :base64 or :binary
    # @return [Hash] {text:, usage:}
    def analyze_image(image_data:, prompt:, format: :base64)
      raise NotImplementedError, "#{self.class} must implement #analyze_image"
    end

    # Extract structured data according to a JSON schema
    # @param messages [Array<Hash>] Array of {role:, content:} messages
    # @param schema [Hash] JSON Schema for the expected output
    # @return [Hash] Extracted data matching the schema
    def extract_structured(messages:, schema:)
      raise NotImplementedError, "#{self.class} must implement #extract_structured"
    end

    # Check if the provider supports vision/image analysis
    def supports_vision?
      true
    end

    # Check if the provider supports structured output
    def supports_structured_output?
      true
    end

    # Provider name for logging and identification
    def provider_name
      raise NotImplementedError, "#{self.class} must implement #provider_name"
    end

    protected

    def api_key
      @config[:api_key]
    end

    def client
      raise NotImplementedError, "#{self.class} must implement #client"
    end

    # Format messages for the specific provider
    def format_messages(messages)
      messages.map { |m| format_message(m) }
    end

    def format_message(msg)
      { role: msg[:role], content: msg[:content] }
    end

    # Log API calls for debugging
    def log_request(method, details = {})
      Rails.logger.debug "[#{provider_name}] #{method}: #{details.to_json}"
    end

    def log_response(method, response)
      Rails.logger.debug "[#{provider_name}] #{method} response: #{response.to_json.truncate(500)}"
    end

    def log_error(method, error)
      Rails.logger.error "[#{provider_name}] #{method} error: #{error.message}"
    end
  end
end
