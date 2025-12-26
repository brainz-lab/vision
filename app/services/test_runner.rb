# TestRunner orchestrates running a full visual test suite for a project.
# It creates snapshots for all enabled pages and browser configs.

class TestRunner
  attr_reader :test_run

  def initialize(test_run)
    @test_run = test_run
  end

  def run!
    # Start the test run
    @test_run.start!

    project = @test_run.project
    pages = project.pages.enabled.ordered
    browser_configs = project.browser_configs.enabled

    # Calculate total pages
    total = pages.count * browser_configs.count
    @test_run.update!(total_pages: total, pending_count: total)

    # Queue capture jobs for each page/browser combination
    pages.find_each do |page|
      browser_configs.find_each do |browser_config|
        # Create pending snapshot
        snapshot = page.snapshots.create!(
          browser_config: browser_config,
          test_run: @test_run,
          branch: @test_run.branch,
          commit_sha: @test_run.commit_sha,
          environment: @test_run.environment,
          triggered_by: @test_run.triggered_by,
          status: 'pending'
        )

        # Queue the capture job
        CaptureScreenshotJob.perform_later(snapshot.id)
      end
    end

    @test_run
  end

  def self.run_for_project!(project, **options)
    test_run = project.test_runs.create!(
      branch: options[:branch] || 'main',
      commit_sha: options[:commit_sha],
      commit_message: options[:commit_message],
      environment: options[:environment] || 'staging',
      triggered_by: options[:triggered_by] || 'api',
      trigger_source: options[:trigger_source],
      pr_number: options[:pr_number],
      pr_url: options[:pr_url],
      base_branch: options[:base_branch] || 'main',
      status: 'pending'
    )

    new(test_run).run!
  end
end
