module Api
  module V1
    class TestCasesController < BaseController
      before_action :set_test_case, only: [ :show, :update, :destroy ]

      # GET /api/v1/test_cases
      def index
        test_cases = current_project.test_cases.ordered

        if params[:enabled].present?
          test_cases = test_cases.where(enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]))
        end

        render json: {
          test_cases: test_cases.map { |tc| serialize_test_case(tc) }
        }
      end

      # GET /api/v1/test_cases/:id
      def show
        render json: serialize_test_case(@test_case)
      end

      # POST /api/v1/test_cases
      def create
        test_case = current_project.test_cases.new(test_case_params)

        if test_case.save
          render json: serialize_test_case(test_case), status: :created
        else
          render json: { errors: test_case.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/test_cases/:id
      def update
        if @test_case.update(test_case_params)
          render json: serialize_test_case(@test_case)
        else
          render json: { errors: @test_case.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/test_cases/:id
      def destroy
        @test_case.destroy
        head :no_content
      end

      private

      def set_test_case
        @test_case = current_project.test_cases.find(params[:id])
      end

      def test_case_params
        params.permit(
          :name, :description, :enabled, :position,
          tags: [],
          steps: [ :action, :url, :selector, :name, :text, :value, :y, :ms, :timeout ]
        )
      end

      def serialize_test_case(test_case)
        {
          id: test_case.id,
          name: test_case.name,
          description: test_case.description,
          steps: test_case.steps,
          tags: test_case.tags,
          enabled: test_case.enabled,
          position: test_case.position,
          step_count: test_case.step_count,
          screenshot_steps: test_case.screenshot_steps.length,
          created_at: test_case.created_at,
          updated_at: test_case.updated_at
        }
      end
    end
  end
end
