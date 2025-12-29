# frozen_string_literal: true

require "connection_pool"

# VisionWorkerPool manages a pool of pre-warmed Playwright browser instances
# for immediate response to synchronous MCP tool requests.
#
# This pool eliminates cold-start delays by maintaining ready-to-use browser
# workers that implement the same interface as BrowserProviders::Local.
#
# Usage:
#   VisionWorkerPool.with_worker do |worker|
#     worker.navigate(worker.session_id, "https://example.com")
#     result = worker.screenshot(worker.session_id)
#   end
#
# Configuration (environment variables):
#   VISION_WORKER_COUNT - Number of pre-warmed browsers (default: 4)
#   VISION_WORKER_TIMEOUT - Checkout timeout in seconds (default: 120)
#   PREWARM_VISION_WORKERS - Pre-warm on boot if "true"
#
class VisionWorkerPool
  POOL_SIZE = ENV.fetch("VISION_WORKER_COUNT", 4).to_i
  POOL_TIMEOUT = ENV.fetch("VISION_WORKER_TIMEOUT", 120).to_i

  class << self
    # Checkout a worker from the pool, execute the block, then return it
    # @yield [VisionWorker] A pre-warmed browser worker
    # @return [Object] The result of the block
    def with_worker(&block)
      pool.with do |worker|
        worker.checkout!
        begin
          # Reinitialize if worker is unhealthy
          if !worker.healthy?
            Rails.logger.warn "[VisionWorkerPool] Worker #{worker.session_id} unhealthy, reinitializing..."
            worker.reinitialize!
          end
          yield worker
        ensure
          worker.checkin!
        end
      end
    end

    # Get or create the connection pool
    # @return [ConnectionPool] The worker pool
    def pool
      @pool ||= ConnectionPool.new(size: POOL_SIZE, timeout: POOL_TIMEOUT) do
        Rails.logger.info "[VisionWorkerPool] Creating new VisionWorker..."
        VisionWorker.new
      end
    end

    # Shutdown all workers and clear the pool
    def shutdown!
      Rails.logger.info "[VisionWorkerPool] Shutting down #{POOL_SIZE} workers..."
      @pool&.shutdown { |worker| worker.cleanup! }
      @pool = nil
      Rails.logger.info "[VisionWorkerPool] Shutdown complete"
    end

    # Get pool statistics
    # @return [Hash] Pool stats including size and availability
    def stats
      {
        size: POOL_SIZE,
        available: @pool&.available || 0,
        timeout: POOL_TIMEOUT,
        initialized: @pool.present?
      }
    end

    # Pre-warm the worker pool by forcing creation of all workers
    def warmup!
      return if @pool.present?

      Rails.logger.info "[VisionWorkerPool] Pre-warming #{POOL_SIZE} workers..."
      start = Time.current

      # Force pool creation
      pool

      # Checkout and immediately return each worker to ensure they're initialized
      threads = POOL_SIZE.times.map do
        Thread.new do
          pool.with { |worker| worker.healthy? }
        end
      end
      threads.each(&:join)

      duration = ((Time.current - start) * 1000).round
      Rails.logger.info "[VisionWorkerPool] Pool ready with #{POOL_SIZE} workers (#{duration}ms)"
    end

    # Check health of all workers
    # @return [Hash] Health status of the pool
    def health_check
      return { status: "not_initialized", workers: [] } unless @pool

      workers = []
      checked = 0

      # Try to check as many workers as we can without blocking too long
      begin
        Timeout.timeout(5) do
          loop do
            break if checked >= POOL_SIZE
            pool.with do |worker|
              workers << {
                session_id: worker.session_id,
                healthy: worker.healthy?,
                age_seconds: (Time.current - worker.created_at).to_i,
                stale: worker.stale?
              }
              checked += 1
            end
          end
        end
      rescue Timeout::Error
        # Some workers are busy, that's fine
      end

      {
        status: "ok",
        pool_size: POOL_SIZE,
        workers_checked: checked,
        workers: workers
      }
    end

    # Refresh any stale workers in the pool
    # Called periodically to ensure workers stay fresh
    def refresh_stale_workers!
      return unless @pool

      refreshed = 0
      POOL_SIZE.times do
        begin
          Timeout.timeout(1) do
            pool.with do |worker|
              if worker.stale? || !worker.healthy?
                Rails.logger.info "[VisionWorkerPool] Refreshing stale worker #{worker.session_id}"
                worker.reinitialize!
                refreshed += 1
              end
            end
          end
        rescue Timeout::Error
          # Worker is busy, skip it
        end
      end

      Rails.logger.info "[VisionWorkerPool] Refreshed #{refreshed} workers" if refreshed > 0
      refreshed
    end
  end
end
