module Api
  module V1
    class BrowserConfigsController < BaseController
      before_action :set_browser_config, only: [ :show, :update, :destroy ]

      # GET /api/v1/browser_configs
      def index
        browser_configs = current_project.browser_configs

        render json: {
          browser_configs: browser_configs.map { |bc| serialize_browser_config(bc) }
        }
      end

      # GET /api/v1/browser_configs/:id
      def show
        render json: serialize_browser_config(@browser_config)
      end

      # POST /api/v1/browser_configs
      def create
        browser_config = current_project.browser_configs.new(browser_config_params)

        if browser_config.save
          render json: serialize_browser_config(browser_config), status: :created
        else
          render json: { errors: browser_config.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/browser_configs/:id
      def update
        if @browser_config.update(browser_config_params)
          render json: serialize_browser_config(@browser_config)
        else
          render json: { errors: @browser_config.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/browser_configs/:id
      def destroy
        @browser_config.destroy
        head :no_content
      end

      private

      def set_browser_config
        @browser_config = current_project.browser_configs.find(params[:id])
      end

      def browser_config_params
        params.permit(
          :browser, :name, :width, :height,
          :device_scale_factor, :is_mobile, :has_touch,
          :user_agent, :enabled
        )
      end

      def serialize_browser_config(bc)
        {
          id: bc.id,
          browser: bc.browser,
          name: bc.name,
          display_name: bc.display_name,
          width: bc.width,
          height: bc.height,
          device_scale_factor: bc.device_scale_factor,
          is_mobile: bc.is_mobile,
          has_touch: bc.has_touch,
          user_agent: bc.user_agent,
          enabled: bc.enabled,
          created_at: bc.created_at
        }
      end
    end
  end
end
