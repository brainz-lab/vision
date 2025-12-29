# frozen_string_literal: true

# VisionWorkerPool Lifecycle Management
#
# This initializer handles:
# - Optional pre-warming of browser workers on boot
# - Graceful shutdown on application exit
# - Periodic health checks and stale worker refresh (optional)
#
# Configuration via environment variables:
# - VISION_WORKER_COUNT: Number of pre-warmed browsers (default: 4)
# - VISION_WORKER_TIMEOUT: Checkout timeout in seconds (default: 120)
# - PREWARM_VISION_WORKERS: Set to "true" to pre-warm on boot
#

Rails.application.config.after_initialize do
  # Skip in test environment to avoid slow test startup
  next if Rails.env.test?

  # Pre-warm workers on boot if requested
  # This eliminates cold-start delay for the first requests
  if ENV["PREWARM_VISION_WORKERS"] == "true"
    Thread.new do
      begin
        # Wait a bit for Rails to fully initialize
        sleep 5
        VisionWorkerPool.warmup!
      rescue => e
        Rails.logger.error "[VisionWorkerPool] Failed to pre-warm: #{e.message}"
      end
    end
  end

  # Log pool configuration
  Rails.logger.info "[VisionWorkerPool] Configured: #{VisionWorkerPool::POOL_SIZE} workers, #{VisionWorkerPool::POOL_TIMEOUT}s timeout"
end

# Graceful shutdown - cleanup all browser processes
at_exit do
  next if Rails.env.test?

  begin
    VisionWorkerPool.shutdown!
  rescue => e
    # Ignore errors during shutdown
    Rails.logger.warn "[VisionWorkerPool] Shutdown error: #{e.message}" rescue nil
  end
end
