module Api
  module V1
    class PagesController < BaseController
      before_action :set_page, only: [:show, :update, :destroy]

      # GET /api/v1/pages
      def index
        pages = current_project.pages.ordered

        render json: {
          pages: pages.map { |page| serialize_page(page) }
        }
      end

      # GET /api/v1/pages/:id
      def show
        render json: serialize_page(@page, include_baselines: true)
      end

      # POST /api/v1/pages
      def create
        page = current_project.pages.new(page_params)

        if page.save
          render json: serialize_page(page), status: :created
        else
          render json: { errors: page.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/pages/:id
      def update
        if @page.update(page_params)
          render json: serialize_page(@page)
        else
          render json: { errors: @page.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/pages/:id
      def destroy
        @page.destroy
        head :no_content
      end

      private

      def set_page
        @page = current_project.pages.find(params[:id])
      end

      def page_params
        params.permit(
          :name, :path, :slug, :wait_ms, :enabled, :position,
          viewport: [:width, :height],
          wait_for: [:selector, :timeout],
          actions: [:type, :selector, :y, :ms, :text, :value],
          hide_selectors: [],
          mask_selectors: []
        )
      end

      def serialize_page(page, include_baselines: false)
        data = {
          id: page.id,
          name: page.name,
          path: page.path,
          slug: page.slug,
          full_url: page.full_url,
          viewport: page.effective_viewport,
          wait_ms: page.effective_wait_ms,
          actions: page.all_actions,
          hide_selectors: page.effective_hide_selectors,
          mask_selectors: page.effective_mask_selectors,
          enabled: page.enabled,
          position: page.position,
          created_at: page.created_at,
          updated_at: page.updated_at
        }

        if include_baselines
          data[:baselines] = page.baselines.active.map do |baseline|
            {
              id: baseline.id,
              browser_config_id: baseline.browser_config_id,
              browser_config_name: baseline.browser_config.name,
              branch: baseline.branch,
              approved_at: baseline.approved_at,
              screenshot_url: baseline.screenshot_url
            }
          end
        end

        data
      end
    end
  end
end
