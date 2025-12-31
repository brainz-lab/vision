class TestRunChannel < ApplicationCable::Channel
  def subscribed
    test_run = TestRun.find(params[:test_run_id])
    stream_for test_run
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  # Broadcast methods for real-time updates
  def self.broadcast_progress(test_run)
    broadcast_to(test_run, {
      type: "progress",
      summary: test_run.summary,
      progress: test_run.progress,
      status: test_run.status
    })
  end

  def self.broadcast_comparison(test_run, comparison)
    broadcast_to(test_run, {
      type: "comparison",
      comparison: {
        id: comparison.id,
        page_name: comparison.page.name,
        status: comparison.status,
        diff_percentage: comparison.diff_percentage
      }
    })
  end

  def self.broadcast_complete(test_run)
    broadcast_to(test_run, {
      type: "complete",
      status: test_run.status,
      summary: test_run.summary,
      duration_ms: test_run.duration_ms
    })
  end
end
