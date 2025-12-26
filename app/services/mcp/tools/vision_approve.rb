module Mcp
  module Tools
    class VisionApprove < Base
      DESCRIPTION = "Approve visual changes and update baseline"
      SCHEMA = {
        type: 'object',
        properties: {
          comparison_id: {
            type: 'string',
            description: 'Comparison ID to approve'
          },
          update_baseline: {
            type: 'boolean',
            default: true,
            description: 'Update baseline with new screenshot'
          }
        },
        required: ['comparison_id']
      }.freeze

      def call(args)
        comparison = Comparison.joins(snapshot: { page: :project })
                              .where(projects: { id: project.id })
                              .find_by(id: args[:comparison_id])

        return error("Comparison not found") unless comparison

        if comparison.review_status == 'approved'
          return success({
            message: 'Already approved',
            comparison_id: comparison.id
          })
        end

        update_baseline = args[:update_baseline] != false

        if update_baseline
          comparison.snapshot.promote_to_baseline!
        end

        comparison.approve!('mcp@vision.brainzlab.ai')

        success({
          approved: true,
          baseline_updated: update_baseline,
          comparison_id: comparison.id,
          page_name: comparison.page.name,
          message: "Changes approved for #{comparison.page.name}#{update_baseline ? ' and baseline updated' : ''}"
        })
      rescue => e
        error("Failed to approve: #{e.message}")
      end
    end
  end
end
