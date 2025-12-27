# Fix for solid_queue 1.2.4 compatibility with Rails 8.1
# The 'silence' method was removed from Logger in Rails 8.1
# solid_queue calls ActiveRecord::Base.logger.silence which fails with plain Logger

Rails.application.config.after_initialize do
  # Ensure ActiveRecord::Base.logger is an ActiveSupport::Logger with silence support
  if ActiveRecord::Base.logger && !ActiveRecord::Base.logger.respond_to?(:silence)
    require "active_support/logger"
    require "active_support/logger_silence"

    # Wrap the existing logger in an ActiveSupport::Logger
    original_logger = ActiveRecord::Base.logger
    new_logger = ActiveSupport::Logger.new(original_logger.instance_variable_get(:@logdev)&.dev || $stdout)
    new_logger.level = original_logger.level
    new_logger.formatter = original_logger.formatter
    ActiveRecord::Base.logger = new_logger
  end
end

# Also patch Logger class directly as a fallback for forked processes
require "active_support/logger_silence"
unless Logger.method_defined?(:silence)
  class ::Logger
    def silence(severity = Logger::ERROR)
      old_level = level
      self.level = severity
      yield self
    ensure
      self.level = old_level
    end
  end
end
