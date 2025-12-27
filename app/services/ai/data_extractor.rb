# frozen_string_literal: true

module Ai
  # Structured data extraction from web pages using LLM
  # Implements page.extract() functionality
  class DataExtractor
    attr_reader :browser, :session_id, :llm, :project

    def initialize(browser:, session_id:, llm:, project: nil)
      @browser = browser
      @session_id = session_id
      @llm = llm
      @project = project
    end

    # Extract structured data according to a schema
    # @param instruction [String] What to extract
    # @param schema [Hash, nil] JSON Schema for output
    # @param use_vision [Boolean] Use screenshot for extraction
    # @return [Hash] Extracted data
    def extract(instruction, schema: nil, use_vision: true)
      # Get page content
      html = @browser.page_content(@session_id, format: :html)
      url = @browser.current_url(@session_id)

      if use_vision && @llm.supports_vision?
        extract_with_vision(instruction, html, url, schema)
      else
        extract_from_text(instruction, html, url, schema)
      end
    end

    # Extract data using vision (screenshot + HTML)
    def extract_with_vision(instruction, html, url, schema = nil)
      screenshot_result = @browser.screenshot(@session_id, full_page: false)

      prompt = build_extraction_prompt(instruction, html, url, schema)

      if schema
        # Use structured output
        messages = [{ role: "user", content: prompt }]
        @llm.extract_structured(messages: messages, schema: schema)
      else
        # Use vision for free-form extraction
        response = @llm.analyze_image(
          image_data: screenshot_result[:data],
          prompt: prompt,
          format: :binary
        )

        parse_extraction_response(response[:text])
      end
    end

    # Extract data from text only (no screenshot)
    def extract_from_text(instruction, html, url, schema = nil)
      # Simplify HTML for token efficiency
      text = extract_visible_text(html)

      prompt = <<~PROMPT
        Extract the following from this web page:
        #{instruction}

        URL: #{url}

        Page content:
        #{text.truncate(10000)}

        #{schema ? "Return data matching this schema:\n#{JSON.pretty_generate(schema)}" : "Return the extracted data as JSON."}
      PROMPT

      if schema
        messages = [{ role: "user", content: prompt }]
        @llm.extract_structured(messages: messages, schema: schema)
      else
        response = @llm.complete(messages: [{ role: "user", content: prompt }])
        parse_extraction_response(response[:text])
      end
    end

    # Extract specific element types
    def extract_table(selector = "table")
      result = @browser.evaluate(@session_id, <<~JS)
        (function() {
          const table = document.querySelector('#{selector}');
          if (!table) return null;

          const headers = Array.from(table.querySelectorAll('th'))
            .map(th => th.textContent.trim());

          const rows = Array.from(table.querySelectorAll('tbody tr'))
            .map(tr => {
              const cells = Array.from(tr.querySelectorAll('td'))
                .map(td => td.textContent.trim());

              if (headers.length > 0) {
                return headers.reduce((obj, header, i) => {
                  obj[header] = cells[i] || '';
                  return obj;
                }, {});
              }
              return cells;
            });

          return { headers, rows, rowCount: rows.length };
        })()
      JS

      result || { headers: [], rows: [], rowCount: 0 }
    end

    # Extract all links from the page
    def extract_links(filter: nil)
      result = @browser.evaluate(@session_id, <<~JS)
        Array.from(document.querySelectorAll('a'))
          .map(a => ({
            text: a.textContent.trim(),
            href: a.href,
            title: a.title || null
          }))
          .filter(l => l.href && l.text)
      JS

      links = result || []

      if filter
        links.select { |l| l[:text].include?(filter) || l[:href].include?(filter) }
      else
        links
      end
    end

    # Extract form fields
    def extract_form(selector = "form")
      @browser.evaluate(@session_id, <<~JS)
        (function() {
          const form = document.querySelector('#{selector}');
          if (!form) return null;

          return {
            action: form.action,
            method: form.method,
            fields: Array.from(form.querySelectorAll('input, select, textarea'))
              .map(el => ({
                name: el.name,
                type: el.type || el.tagName.toLowerCase(),
                value: el.value,
                required: el.required,
                placeholder: el.placeholder,
                label: document.querySelector(`label[for="${el.id}"]`)?.textContent?.trim()
              }))
          };
        })()
      JS
    end

    # Extract meta information
    def extract_meta
      @browser.evaluate(@session_id, <<~JS)
        (function() {
          const getMeta = (name) => {
            const el = document.querySelector(`meta[name="${name}"], meta[property="${name}"]`);
            return el ? el.content : null;
          };

          return {
            title: document.title,
            description: getMeta('description'),
            keywords: getMeta('keywords'),
            author: getMeta('author'),
            ogTitle: getMeta('og:title'),
            ogDescription: getMeta('og:description'),
            ogImage: getMeta('og:image'),
            canonical: document.querySelector('link[rel="canonical"]')?.href
          };
        })()
      JS
    end

    private

    def build_extraction_prompt(instruction, html, url, schema)
      text = extract_visible_text(html)

      prompt = <<~PROMPT
        Extract the following from this web page:
        #{instruction}

        URL: #{url}

        Visible text (truncated):
        #{text.truncate(5000)}

        Analyze both the screenshot and the text to extract the requested data.
      PROMPT

      if schema
        prompt += "\n\nReturn data matching this JSON schema:\n#{JSON.pretty_generate(schema)}"
      else
        prompt += "\n\nReturn the extracted data as valid JSON."
      end

      prompt
    end

    def extract_visible_text(html)
      doc = Nokogiri::HTML(html)

      # Remove script and style elements
      doc.css("script, style, noscript, svg, path").remove

      # Get text content
      doc.css("body").text.gsub(/\s+/, " ").strip
    rescue
      ""
    end

    def parse_extraction_response(text)
      # Try to extract JSON from response
      json_match = text.match(/```json\s*([\s\S]*?)\s*```/) ||
                   text.match(/```\s*([\s\S]*?)\s*```/) ||
                   text.match(/(\{[\s\S]*\})/) ||
                   text.match(/(\[[\s\S]*\])/)

      if json_match
        JSON.parse(json_match[1], symbolize_names: true)
      else
        # Return raw text if no JSON found
        { raw: text }
      end
    rescue JSON::ParserError
      { raw: text }
    end
  end
end
