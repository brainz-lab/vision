# frozen_string_literal: true

module BrowserProviders
  # Factory for creating browser provider instances
  class Factory
    PROVIDERS = {
      "local" => "BrowserProviders::Local",
      "hyperbrowser" => "BrowserProviders::Hyperbrowser",
      "browserbase" => "BrowserProviders::Browserbase",
      "stagehand" => "BrowserProviders::Stagehand",
      "director" => "BrowserProviders::Director"
    }.freeze

    class << self
      # Create a provider instance by name
      # @param provider_name [String] Provider name
      # @param config [Hash] Provider configuration
      # @return [BrowserProviders::Base] Provider instance
      def for(provider_name, config = {})
        provider_class = PROVIDERS[provider_name.to_s]
        raise ArgumentError, "Unknown browser provider: #{provider_name}. Available: #{PROVIDERS.keys.join(', ')}" unless provider_class

        provider_class.constantize.new(config)
      end

      # Create a provider instance for a project
      # @param project [Project] Project with browser provider configuration
      # @param provider_override [String, nil] Optional provider override
      # @return [BrowserProviders::Base] Provider instance
      def for_project(project, provider_override: nil)
        provider_name = provider_override || project.default_browser_provider || "local"
        config = project.browser_provider_config(provider_name)

        self.for(provider_name, config)
      end

      # List all available providers
      # @return [Array<String>] Provider names
      def available_providers
        PROVIDERS.keys
      end

      # List cloud providers only
      # @return [Array<String>] Cloud provider names
      def cloud_providers
        PROVIDERS.keys - ["local"]
      end

      # Check if a provider is available
      # @param provider_name [String] Provider name
      # @return [Boolean]
      def provider_available?(provider_name)
        PROVIDERS.key?(provider_name.to_s)
      end
    end
  end
end
