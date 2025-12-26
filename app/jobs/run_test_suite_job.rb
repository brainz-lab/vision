class RunTestSuiteJob < ApplicationJob
  queue_as :default

  def perform(test_run_id)
    test_run = TestRun.find(test_run_id)
    TestRunner.new(test_run).run!
  rescue => e
    Rails.logger.error "RunTestSuiteJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    test_run&.error!(e.message)
  end
end
