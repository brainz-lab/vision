# frozen_string_literal: true

module Mcp
  module Tools
    # Extract structured data from web pages using AI
    class VisionExtract < Base
      DESCRIPTION = "Extract structured data from a web page using AI vision. Can extract specific elements, tables, forms, or custom data schemas."

      SCHEMA = {
        type: "object",
        properties: {
          instruction: {
            type: "string",
            description: "What to extract (e.g., 'Extract all product names and prices', 'Get the main article content')"
          },
          url: {
            type: "string",
            description: "URL to extract from (required if no session_id)"
          },
          session_id: {
            type: "string",
            description: "Existing browser session ID"
          },
          schema: {
            type: "object",
            description: "JSON schema for structured output"
          },
          extract_type: {
            type: "string",
            enum: %w[custom table links form meta],
            default: "custom",
            description: "Type of extraction: custom (AI-powered), table (HTML tables), links (all links), form (form fields), meta (page metadata)"
          },
          table_selector: {
            type: "string",
            default: "table",
            description: "CSS selector for table extraction"
          },
          link_filter: {
            type: "string",
            description: "Filter links by text or href content"
          },
          form_selector: {
            type: "string",
            default: "form",
            description: "CSS selector for form extraction"
          },
          model: {
            type: "string",
            enum: %w[claude-sonnet-4 claude-opus-4 gpt-4o gpt-4o-mini gemini-2.5-flash gemini-2.0-flash],
            default: "claude-sonnet-4",
            description: "LLM model for AI extraction"
          },
          use_vision: {
            type: "boolean",
            default: true,
            description: "Use screenshot for extraction (more accurate but slower)"
          },
          browser_provider: {
            type: "string",
            enum: %w[local hyperbrowser browserbase stagehand director],
            default: "local",
            description: "Browser provider (only used if creating new session)"
          },
          keep_session: {
            type: "boolean",
            default: false,
            description: "Keep the browser session open after extraction"
          }
        },
        required: %w[instruction]
      }.freeze

      def call(args)
        instruction = args[:instruction]
        url = args[:url]
        session_id = args[:session_id]
        extract_type = (args[:extract_type] || "custom").to_sym
        keep_session = args.fetch(:keep_session, false)

        # Get or create session
        manager = BrowserSessionManager.new(project)

        if session_id.present?
          session = project.browser_sessions.find(session_id)
        else
          raise ArgumentError, "url is required when no session_id provided" unless url.present?

          session = manager.create_session(
            provider: args[:browser_provider] || project.default_browser_provider,
            start_url: url,
            viewport: { width: 1280, height: 720 }
          )
        end

        browser = manager.provider_for(session)

        # Navigate if URL provided and different
        if url.present?
          current = browser.current_url(session.provider_session_id) rescue nil
          if current != url
            browser.navigate(session.provider_session_id, url)
            sleep(1) # Wait for page load
          end
        end

        # Create extractor
        llm = LlmProviders::Factory.for_project(
          project,
          model: args[:model] || project.default_llm_model
        )

        extractor = Ai::DataExtractor.new(
          browser: browser,
          session_id: session.provider_session_id,
          llm: llm,
          project: project
        )

        # Perform extraction based on type
        data = case extract_type
        when :table
          extractor.extract_table(args[:table_selector] || "table")
        when :links
          extractor.extract_links(filter: args[:link_filter])
        when :form
          extractor.extract_form(args[:form_selector] || "form")
        when :meta
          extractor.extract_meta
        else # :custom
          extractor.extract(
            instruction,
            schema: args[:schema],
            use_vision: args.fetch(:use_vision, true)
          )
        end

        current_url = browser.current_url(session.provider_session_id) rescue url

        # Close session unless keeping
        unless keep_session
          manager.close_session(session)
          session = nil
        end

        response = {
          success: true,
          data: data,
          url: current_url,
          extract_type: extract_type.to_s
        }

        if keep_session && session
          response[:session_id] = session.id
        end

        success(response)
      rescue ActiveRecord::RecordNotFound
        error("Session not found: #{session_id}")
      rescue ArgumentError => e
        error(e.message)
      rescue => e
        error("Failed to extract data: #{e.message}")
      end
    end
  end
end
