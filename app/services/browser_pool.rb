# BrowserPool manages Playwright browser instances using connection pooling
# to efficiently share browser resources across multiple screenshot captures.

require 'connection_pool'
require 'playwright'

class BrowserPool
  POOL_SIZE = ENV.fetch('BROWSER_POOL_SIZE', 5).to_i
  POOL_TIMEOUT = ENV.fetch('BROWSER_POOL_TIMEOUT', 30).to_i

  class << self
    def with_browser(browser_config, &block)
      pool = pool_for(browser_config)
      pool.with do |context|
        page = context.new_page
        begin
          yield page
        ensure
          page.close rescue nil
        end
      end
    end

    def shutdown!
      @pools&.each_value do |pool|
        pool.shutdown { |context| context.browser.close rescue nil }
      end
      @pools = nil
      @playwright&.stop
      @playwright = nil
    end

    private

    def pool_for(browser_config)
      @pools ||= {}
      key = pool_key(browser_config)

      @pools[key] ||= create_pool(browser_config)
    end

    def pool_key(browser_config)
      "#{browser_config.browser}_#{browser_config.width}x#{browser_config.height}"
    end

    def create_pool(browser_config)
      ConnectionPool.new(size: POOL_SIZE, timeout: POOL_TIMEOUT) do
        create_browser_context(browser_config)
      end
    end

    def create_browser_context(browser_config)
      execution = Playwright.create(playwright_cli_executable_path: find_playwright_path)
      playwright = execution.playwright
      browser = playwright.send(browser_config.browser.to_sym).launch(
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox']
      )

      context_options = {
        viewport: {
          width: browser_config.width,
          height: browser_config.height
        }
      }
      context_options[:deviceScaleFactor] = browser_config.device_scale_factor if browser_config.device_scale_factor
      context_options[:isMobile] = browser_config.is_mobile if browser_config.is_mobile
      context_options[:hasTouch] = browser_config.has_touch if browser_config.has_touch
      context_options[:userAgent] = browser_config.user_agent if browser_config.user_agent

      browser.new_context(**context_options)
    end

    def find_playwright_path
      # Try to find npx playwright in various locations
      paths = [
        'npx playwright',
        '/usr/local/bin/npx playwright',
        File.join(ENV['HOME'], '.npm-global/bin/npx playwright')
      ]

      paths.find { |path| system("which #{path.split.first} > /dev/null 2>&1") } || 'npx playwright'
    end
  end
end
