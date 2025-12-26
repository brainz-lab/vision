module Mcp
  module Tools
    class VisionCompare < Base
      DESCRIPTION = "Compare current page state to baseline"
      SCHEMA = {
        type: 'object',
        properties: {
          page: {
            type: 'string',
            description: 'Page name, slug, or path'
          },
          url: {
            type: 'string',
            description: 'URL to capture and compare (alternative to page)'
          },
          threshold: {
            type: 'number',
            description: 'Diff threshold (0.01 = 1%)',
            default: 0.01
          },
          viewport: {
            type: 'string',
            enum: ['desktop', 'mobile'],
            default: 'desktop'
          }
        }
      }.freeze

      def call(args)
        page = find_page(args)
        return error("Page not found") unless page

        browser_config = find_browser_config(args[:viewport])
        threshold = args[:threshold] || project.threshold

        # Check for existing baseline
        baseline = page.current_baseline(browser_config)

        # Capture current state
        snapshot = page.snapshots.create!(
          browser_config: browser_config,
          triggered_by: 'mcp',
          status: 'pending'
        )

        ScreenshotService.new(snapshot).capture

        unless baseline
          # No baseline - create one
          snapshot.promote_to_baseline!
          return success({
            status: 'baseline_created',
            message: "No baseline existed. Created new baseline from current screenshot.",
            snapshot_id: snapshot.id,
            screenshot_url: snapshot.screenshot_url
          })
        end

        # Compare to baseline
        comparison = ComparisonService.new(baseline, snapshot, threshold: threshold).compare

        success({
          status: comparison.status,
          passed: comparison.passed?,
          diff_percentage: comparison.diff_percentage,
          diff_pixels: comparison.diff_pixels,
          threshold: threshold,
          within_threshold: comparison.within_threshold,
          comparison_id: comparison.id,
          snapshot_url: snapshot.screenshot_url,
          baseline_url: baseline.screenshot_url,
          diff_url: comparison.diff_image_url,
          message: comparison.passed? ?
            "Visual test passed (#{comparison.diff_percentage.round(2)}% difference)" :
            "Visual difference detected: #{comparison.diff_percentage.round(2)}% changed"
        })
      rescue => e
        error("Comparison failed: #{e.message}")
      end

      private

      def find_page(args)
        if args[:url]
          uri = URI.parse(args[:url])
          path = uri.path.presence || '/'
          project.pages.find_by(path: path)
        elsif args[:page]
          project.pages.find_by(slug: args[:page]) ||
            project.pages.find_by(name: args[:page]) ||
            project.pages.find_by(path: args[:page])
        else
          nil
        end
      end

      def find_browser_config(viewport)
        case viewport
        when 'mobile'
          project.browser_configs.find_by(is_mobile: true) || project.browser_configs.first
        else
          project.browser_configs.find_by(is_mobile: false) || project.browser_configs.first
        end
      end
    end
  end
end
