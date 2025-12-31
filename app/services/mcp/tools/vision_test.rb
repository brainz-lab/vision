module Mcp
  module Tools
    class VisionTest < Base
      DESCRIPTION = "Run visual regression test for all pages"
      SCHEMA = {
        type: "object",
        properties: {
          branch: {
            type: "string",
            description: "Git branch name"
          },
          pages: {
            type: "array",
            items: { type: "string" },
            description: "Specific page names/slugs to test (optional, tests all if omitted)"
          },
          environment: {
            type: "string",
            enum: [ "staging", "production" ],
            default: "staging"
          }
        }
      }.freeze

      MAX_WAIT_TIME = 120 # seconds

      def call(args)
        # Create test run
        test_run = project.test_runs.create!(
          branch: args[:branch] || "main",
          environment: args[:environment] || "staging",
          triggered_by: "mcp",
          status: "pending"
        )

        # Get pages to test
        pages = if args[:pages]&.any?
          project.pages.enabled.where(slug: args[:pages])
                   .or(project.pages.enabled.where(name: args[:pages]))
        else
          project.pages.enabled
        end

        browser_configs = project.browser_configs.enabled

        # Calculate total
        total = pages.count * browser_configs.count
        test_run.update!(total_pages: total, pending_count: total)

        if total.zero?
          test_run.update!(status: "passed")
          return success({
            test_run_id: test_run.id,
            status: "passed",
            message: "No pages configured for testing",
            summary: test_run.summary
          })
        end

        # Run tests synchronously for MCP
        test_run.start!

        pages.each do |page|
          browser_configs.each do |browser_config|
            run_single_test(test_run, page, browser_config)
          end
        end

        test_run.complete!

        success({
          test_run_id: test_run.id,
          status: test_run.status,
          summary: test_run.summary,
          failed_pages: test_run.failed_comparisons.map { |c| c.page.name },
          message: test_run.passed? ?
            "All #{total} visual tests passed" :
            "#{test_run.failed_count} of #{total} tests failed"
        })
      rescue => e
        test_run&.error!
        error("Test run failed: #{e.message}")
      end

      private

      def run_single_test(test_run, page, browser_config)
        # Create snapshot
        snapshot = page.snapshots.create!(
          browser_config: browser_config,
          test_run: test_run,
          branch: test_run.branch,
          environment: test_run.environment,
          triggered_by: "mcp",
          status: "pending"
        )

        # Capture screenshot
        begin
          ScreenshotService.new(snapshot).capture

          # Get baseline
          baseline = page.current_baseline(browser_config)

          if baseline
            # Compare
            ComparisonService.new(baseline, snapshot).compare
          else
            # Create baseline
            snapshot.promote_to_baseline!
            test_run.increment!(:passed_count)
          end
        rescue => e
          snapshot.mark_error!(e.message)
          test_run.increment!(:error_count)
        end
      end
    end
  end
end
