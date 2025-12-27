# frozen_string_literal: true

module LlmProviders
  # Factory for creating LLM provider instances
  # Maps model names to their respective providers
  class Factory
    # Map model names to provider types
    PROVIDER_MAP = {
      # Anthropic Claude models
      "claude-sonnet-4" => :anthropic,
      "claude-sonnet-4-20250514" => :anthropic,
      "claude-opus-4" => :anthropic,
      "claude-opus-4-20250514" => :anthropic,
      "claude-3-5-sonnet" => :anthropic,
      "claude-3-5-sonnet-20241022" => :anthropic,

      # OpenAI models
      "gpt-4o" => :openai,
      "gpt-4o-mini" => :openai,
      "gpt-4-turbo" => :openai,
      "gpt-4" => :openai,

      # Google Gemini models
      "gemini-2.5-flash" => :gemini,
      "gemini-2.5-flash-preview-05-20" => :gemini,
      "gemini-2.0-flash" => :gemini,
      "gemini-2.0-flash-exp" => :gemini,
      "gemini-1.5-pro" => :gemini,
      "gemini-1.5-flash" => :gemini
    }.freeze

    # Provider classes
    PROVIDERS = {
      anthropic: "LlmProviders::Anthropic",
      openai: "LlmProviders::Openai",
      gemini: "LlmProviders::Gemini"
    }.freeze

    class << self
      # Create a provider instance for the given model
      # @param model [String] Model name (e.g., "claude-sonnet-4", "gpt-4o")
      # @param config [Hash] Provider configuration including :api_key
      # @return [LlmProviders::Base] Provider instance
      def for(model:, config: {})
        provider_type = PROVIDER_MAP[model]
        raise ArgumentError, "Unknown model: #{model}. Available: #{PROVIDER_MAP.keys.join(', ')}" unless provider_type

        provider_class = PROVIDERS[provider_type].constantize
        provider_class.new(model: model, config: config)
      end

      # Create a provider instance for a project using its configuration
      # @param project [Project] Project with AI settings
      # @param model [String, nil] Optional model override
      # @return [LlmProviders::Base] Provider instance
      def for_project(project, model: nil)
        model_to_use = model || project.default_llm_model || "claude-sonnet-4"
        provider_type = PROVIDER_MAP[model_to_use]
        raise ArgumentError, "Unknown model: #{model_to_use}" unless provider_type

        config = project.llm_provider_config(provider_type)
        self.for(model: model_to_use, config: config)
      end

      # Get the provider type for a model
      # @param model [String] Model name
      # @return [Symbol] Provider type (:anthropic, :openai, :gemini)
      def provider_for(model)
        PROVIDER_MAP[model]
      end

      # List all available models
      # @return [Array<String>] Model names
      def available_models
        PROVIDER_MAP.keys
      end

      # List all available providers
      # @return [Array<Symbol>] Provider types
      def available_providers
        PROVIDERS.keys
      end

      # Get models for a specific provider
      # @param provider [Symbol] Provider type
      # @return [Array<String>] Model names for that provider
      def models_for_provider(provider)
        PROVIDER_MAP.select { |_, p| p == provider }.keys
      end
    end
  end
end
