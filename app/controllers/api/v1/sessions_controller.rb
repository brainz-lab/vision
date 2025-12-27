# frozen_string_literal: true

module Api
  module V1
    # Browser session management API
    # Handles interactive browser sessions for AI-powered automation
    class SessionsController < BaseController
      before_action :set_session, only: %i[show destroy ai perform extract screenshot state]

      # GET /api/v1/sessions
      # List active sessions
      def index
        sessions = current_project.browser_sessions
                                  .order(created_at: :desc)
                                  .limit(params[:limit] || 20)

        if params[:status].present?
          sessions = sessions.where(status: params[:status])
        else
          sessions = sessions.active
        end

        render json: {
          sessions: sessions.map { |s| session_summary(s) },
          total_active: current_project.browser_sessions.active.count
        }
      end

      # GET /api/v1/sessions/:id
      # Get session details
      def show
        render json: { session: session_details(@session) }
      end

      # POST /api/v1/sessions
      # Create a new browser session
      def create
        manager = BrowserSessionManager.new(current_project)

        options = {
          provider: params[:provider] || current_project.default_browser_provider,
          start_url: params[:start_url],
          viewport: params[:viewport] || { width: 1280, height: 720 }
        }

        @session = manager.create_session(**options)

        render json: {
          session: session_details(@session),
          message: "Session created"
        }, status: :created
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # DELETE /api/v1/sessions/:id
      # Close a browser session
      def destroy
        manager = BrowserSessionManager.new(current_project)
        manager.close_session(@session)

        render json: {
          session: session_summary(@session.reload),
          message: "Session closed"
        }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/sessions/:id/ai
      # Execute AI-powered action (page.ai)
      def ai
        instruction = params.require(:instruction)

        executor = Ai::ActionExecutor.new(
          browser: browser_for_session,
          session_id: @session.provider_session_id,
          llm: llm_for_session,
          project: current_project
        )

        result = executor.execute(instruction)

        # Update session state
        @session.update_state!(url: result[:url]) if result[:url]

        render json: {
          success: result[:success] != false,
          action: result[:action],
          selector: result[:selector],
          value: result[:value],
          url: result[:url],
          reasoning: result[:reasoning],
          error: result[:error]
        }
      rescue => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/sessions/:id/perform
      # Execute direct browser action (page.perform)
      def perform
        action = params.require(:action)
        selector = params[:selector]
        value = params[:value]
        options = params[:options]&.to_unsafe_h || {}

        browser = browser_for_session

        result = case action.to_sym
        when :navigate
          browser.navigate(@session.provider_session_id, value)
        else
          browser.perform_action(
            @session.provider_session_id,
            action: action,
            selector: selector,
            value: value,
            **options.symbolize_keys
          )
        end

        # Update session state
        if result[:url]
          @session.update_state!(url: result[:url])
        end

        render json: {
          success: result[:success] != false,
          url: result[:url] || browser.current_url(@session.provider_session_id),
          error: result[:error]
        }
      rescue => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/sessions/:id/extract
      # Extract structured data from page (page.extract)
      def extract
        instruction = params.require(:instruction)
        schema = params[:schema]&.to_unsafe_h
        use_vision = params.fetch(:use_vision, true)

        extractor = Ai::DataExtractor.new(
          browser: browser_for_session,
          session_id: @session.provider_session_id,
          llm: llm_for_session,
          project: current_project
        )

        data = extractor.extract(
          instruction,
          schema: schema,
          use_vision: use_vision
        )

        render json: {
          success: true,
          data: data,
          url: @session.current_url
        }
      rescue => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end

      # GET /api/v1/sessions/:id/screenshot
      # Capture screenshot of current page
      def screenshot
        browser = browser_for_session
        full_page = params.fetch(:full_page, false)

        result = browser.screenshot(
          @session.provider_session_id,
          full_page: full_page
        )

        # Return as base64 or binary
        if params[:format] == "binary"
          send_data result[:data],
                    type: result[:content_type] || "image/png",
                    disposition: "inline"
        else
          render json: {
            data: Base64.strict_encode64(result[:data]),
            content_type: result[:content_type] || "image/png",
            url: browser.current_url(@session.provider_session_id)
          }
        end
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /api/v1/sessions/:id/state
      # Get current page state
      def state
        browser = browser_for_session

        begin
          url = browser.current_url(@session.provider_session_id)
          title = browser.current_title(@session.provider_session_id)

          @session.update_state!(url: url, title: title)

          render json: {
            session_id: @session.id,
            url: url,
            title: title,
            status: @session.status,
            provider: @session.browser_provider,
            expires_at: @session.expires_at&.iso8601
          }
        rescue => e
          render json: {
            session_id: @session.id,
            status: @session.status,
            error: e.message
          }
        end
      end

      private

      def set_session
        @session = current_project.browser_sessions.find(params[:id])
      end

      def browser_for_session
        BrowserProviders::Factory.for_project(
          current_project,
          provider_override: @session.browser_provider
        )
      end

      def llm_for_session
        model = params[:model] || current_project.default_llm_model
        LlmProviders::Factory.for_project(current_project, model: model)
      end

      def session_summary(session)
        {
          id: session.id,
          provider: session.browser_provider,
          status: session.status,
          current_url: session.current_url,
          created_at: session.created_at.iso8601,
          expires_at: session.expires_at&.iso8601
        }
      end

      def session_details(session)
        {
          id: session.id,
          provider_session_id: session.provider_session_id,
          browser_provider: session.browser_provider,
          status: session.status,
          current_url: session.current_url,
          current_title: session.current_title,
          viewport: session.viewport,
          start_url: session.start_url,
          metadata: session.metadata,
          created_at: session.created_at.iso8601,
          expires_at: session.expires_at&.iso8601,
          closed_at: session.closed_at&.iso8601
        }
      end
    end
  end
end
