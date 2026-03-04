class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  rescue_from(StandardError) do |exception|
    BrainzLab::Reflex.capture(exception, context: { job: self.class.name, arguments: arguments })
    BrainzLab::Recall.error("Job failed: #{self.class.name}", error: exception.message)
    BrainzLab::Signal.trigger("job.failure", severity: :high, details: { job: self.class.name, error: exception.message })
    raise exception
  end
end
