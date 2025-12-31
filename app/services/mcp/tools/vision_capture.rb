module Mcp
  module Tools
    class VisionCapture < Base
      DESCRIPTION = "Capture a screenshot of a URL"
      SCHEMA = {
        type: "object",
        properties: {
          url: {
            type: "string",
            description: "URL to capture"
          },
          name: {
            type: "string",
            description: "Name for the page (for organizing)"
          },
          viewport: {
            type: "string",
            enum: [ "desktop", "mobile", "tablet" ],
            default: "desktop",
            description: "Viewport size preset"
          },
          full_page: {
            type: "boolean",
            default: true,
            description: "Capture full page or just viewport"
          }
        },
        required: [ "url" ]
      }.freeze

      def call(args)
        url = args[:url]
        name = args[:name] || extract_page_name(url)
        viewport = args[:viewport] || "desktop"

        # Find or create page
        uri = URI.parse(url)
        path = uri.path.presence || "/"

        page = project.pages.find_or_create_by!(path: path) do |p|
          p.name = name
          p.slug = name.parameterize
        end

        # Find browser config for viewport
        browser_config = find_browser_config(viewport)

        # Create and capture snapshot
        snapshot = page.snapshots.create!(
          browser_config: browser_config,
          triggered_by: "mcp",
          status: "pending"
        )

        # Capture synchronously for MCP
        ScreenshotService.new(snapshot).capture

        success({
          snapshot_id: snapshot.id,
          page_name: page.name,
          url: snapshot.screenshot_url,
          width: snapshot.width,
          height: snapshot.height,
          captured_at: snapshot.captured_at
        })
      rescue => e
        error("Failed to capture screenshot: #{e.message}")
      end

      private

      def extract_page_name(url)
        uri = URI.parse(url)
        path = uri.path.presence || "/"
        path == "/" ? "Homepage" : path.split("/").last&.titleize || "Page"
      end

      def find_browser_config(viewport)
        case viewport
        when "mobile"
          project.browser_configs.find_by(is_mobile: true) ||
            project.browser_configs.create!(browser: "chromium", name: "Mobile", width: 375, height: 812, is_mobile: true, has_touch: true)
        when "tablet"
          project.browser_configs.find_by(width: 768..1024) ||
            project.browser_configs.create!(browser: "chromium", name: "Tablet", width: 768, height: 1024)
        else
          project.browser_configs.find_by(is_mobile: false) ||
            project.browser_configs.first
        end
      end
    end
  end
end
