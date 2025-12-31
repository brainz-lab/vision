module Mcp
  module Tools
    class VisionListFailures < Base
      DESCRIPTION = "List failed visual comparisons that need review"
      SCHEMA = {
        type: "object",
        properties: {
          test_run_id: {
            type: "string",
            description: "Filter by test run ID (optional)"
          },
          limit: {
            type: "integer",
            default: 20,
            description: "Maximum number of results"
          }
        }
      }.freeze

      def call(args)
        comparisons = Comparison.joins(snapshot: { page: :project })
                               .where(projects: { id: project.id })
                               .where(status: "failed")
                               .where(review_status: "pending")
                               .order(created_at: :desc)

        if args[:test_run_id]
          comparisons = comparisons.where(test_run_id: args[:test_run_id])
        end

        comparisons = comparisons.limit(args[:limit] || 20)

        failures = comparisons.map do |comp|
          {
            comparison_id: comp.id,
            page_name: comp.page.name,
            browser_config: comp.snapshot.browser_config.name,
            diff_percentage: comp.diff_percentage&.round(2),
            diff_pixels: comp.diff_pixels,
            threshold: (comp.threshold_used * 100).round(2),
            baseline_url: comp.baseline.screenshot_url,
            snapshot_url: comp.snapshot.screenshot_url,
            diff_url: comp.diff_image_url,
            created_at: comp.created_at
          }
        end

        success({
          count: failures.count,
          failures: failures,
          message: failures.empty? ?
            "No pending failures to review" :
            "#{failures.count} visual test(s) need review"
        })
      end
    end
  end
end
