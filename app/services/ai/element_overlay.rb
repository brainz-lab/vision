# frozen_string_literal: true

module Ai
  # Element overlay system for AI vision
  # Adds numbered markers to interactive elements for LLM identification
  class ElementOverlay
    # JavaScript to inject element overlays
    OVERLAY_SCRIPT = <<~JS
      (function() {
        // Remove existing overlays
        document.querySelectorAll('.vision-ai-overlay').forEach(el => el.remove());

        const interactive = document.querySelectorAll(
          'a, button, input, select, textarea, [role="button"], [onclick], [tabindex]:not([tabindex="-1"])'
        );

        const overlays = [];
        let index = 0;

        interactive.forEach((el) => {
          const rect = el.getBoundingClientRect();

          // Skip invisible elements
          if (rect.width === 0 || rect.height === 0) return;
          if (rect.top < 0 || rect.left < 0) return;
          if (rect.top > window.innerHeight || rect.left > window.innerWidth) return;

          const style = window.getComputedStyle(el);
          if (style.display === 'none' || style.visibility === 'hidden') return;

          index++;

          // Create overlay element
          const overlay = document.createElement('div');
          overlay.className = 'vision-ai-overlay';
          overlay.textContent = index;
          overlay.style.cssText = `
            position: fixed;
            left: ${Math.max(0, rect.left - 2)}px;
            top: ${Math.max(0, rect.top - 2)}px;
            background: rgba(255, 0, 0, 0.85);
            color: white;
            font-size: 11px;
            font-weight: bold;
            font-family: Arial, sans-serif;
            padding: 1px 4px;
            border-radius: 3px;
            z-index: 999999;
            pointer-events: none;
            box-shadow: 0 1px 3px rgba(0,0,0,0.3);
          `;
          document.body.appendChild(overlay);

          overlays.push({
            index: index,
            tag: el.tagName.toLowerCase(),
            type: el.type || null,
            text: (el.textContent || '').trim().substring(0, 100),
            placeholder: el.placeholder || null,
            ariaLabel: el.getAttribute('aria-label'),
            id: el.id || null,
            name: el.name || null,
            href: el.href || null,
            value: el.value || null,
            rect: {
              x: Math.round(rect.x),
              y: Math.round(rect.y),
              width: Math.round(rect.width),
              height: Math.round(rect.height)
            }
          });
        });

        return overlays;
      })()
    JS

    REMOVE_OVERLAY_SCRIPT = <<~JS
      document.querySelectorAll('.vision-ai-overlay').forEach(el => el.remove());
    JS

    class << self
      # Add overlays to interactive elements and return element info
      # @param browser [BrowserProviders::Base] Browser provider
      # @param session_id [String] Session ID
      # @return [Array<Hash>] Interactive elements with overlay info
      def add_overlays(browser, session_id)
        browser.evaluate(session_id, OVERLAY_SCRIPT)
      end

      # Remove all overlays from the page
      # @param browser [BrowserProviders::Base] Browser provider
      # @param session_id [String] Session ID
      def remove_overlays(browser, session_id)
        browser.evaluate(session_id, REMOVE_OVERLAY_SCRIPT)
      end

      # Capture screenshot with overlays
      # @param browser [BrowserProviders::Base] Browser provider
      # @param session_id [String] Session ID
      # @return [Hash] { screenshot: [binary], elements: [Array] }
      def capture_with_overlays(browser, session_id)
        # Add overlays and get element info
        elements = add_overlays(browser, session_id)

        # Small delay for rendering
        sleep(0.1)

        # Capture screenshot
        screenshot = browser.screenshot(session_id, full_page: false)

        # Remove overlays
        remove_overlays(browser, session_id)

        {
          screenshot: screenshot[:data],
          elements: elements
        }
      end

      # Format elements for LLM prompt
      # @param elements [Array<Hash>] Interactive elements
      # @param max_elements [Integer] Maximum elements to include
      # @return [String] Formatted element list
      def format_for_prompt(elements, max_elements: 40)
        elements.first(max_elements).map do |el|
          parts = ["#{el[:index]}. #{el[:tag]}"]

          if el[:type].present?
            parts << "[#{el[:type]}]"
          end

          if el[:text].present? && el[:text].length > 0
            parts << "\"#{el[:text].truncate(40)}\""
          elsif el[:placeholder].present?
            parts << "(placeholder: #{el[:placeholder].truncate(30)})"
          elsif el[:ariaLabel].present?
            parts << "(#{el[:ariaLabel].truncate(30)})"
          end

          if el[:id].present?
            parts << "##{el[:id]}"
          end

          parts.join(" ")
        end.join("\n")
      end

      # Generate selector for an element by index
      # @param elements [Array<Hash>] Interactive elements
      # @param index [Integer] Element index (1-based)
      # @return [String, nil] CSS selector
      def selector_for_index(elements, index)
        element = elements.find { |e| e[:index] == index }
        return nil unless element

        # Try to build a reliable selector
        if element[:id].present?
          "##{element[:id]}"
        elsif element[:text].present? && element[:text].length > 0 && element[:text].length < 50
          "#{element[:tag]}:has-text(\"#{element[:text].gsub('"', '\\"')}\")"
        elsif element[:placeholder].present?
          "#{element[:tag]}[placeholder=\"#{element[:placeholder]}\"]"
        elsif element[:name].present?
          "#{element[:tag]}[name=\"#{element[:name]}\"]"
        elsif element[:ariaLabel].present?
          "[aria-label=\"#{element[:ariaLabel]}\"]"
        else
          # Fallback to position-based clicking
          nil
        end
      end

      # Click element by index using coordinates
      # @param browser [BrowserProviders::Base] Browser provider
      # @param session_id [String] Session ID
      # @param elements [Array<Hash>] Interactive elements
      # @param index [Integer] Element index (1-based)
      def click_by_index(browser, session_id, elements, index)
        element = elements.find { |e| e[:index] == index }
        return { success: false, error: "Element not found" } unless element

        rect = element[:rect]
        x = rect[:x] + (rect[:width] / 2)
        y = rect[:y] + (rect[:height] / 2)

        # Use CDP for precise coordinate clicking if available
        if browser.supports_cdp?
          browser.cdp_send(session_id, "Input.dispatchMouseEvent", {
            type: "mousePressed",
            x: x,
            y: y,
            button: "left",
            clickCount: 1
          })
          browser.cdp_send(session_id, "Input.dispatchMouseEvent", {
            type: "mouseReleased",
            x: x,
            y: y,
            button: "left"
          })
          { success: true }
        else
          # Fallback to evaluate-based clicking
          browser.evaluate(session_id, <<~JS)
            (function() {
              const el = document.elementFromPoint(#{x}, #{y});
              if (el) {
                el.click();
                return true;
              }
              return false;
            })()
          JS
          { success: true }
        end
      rescue => e
        { success: false, error: e.message }
      end
    end
  end
end
