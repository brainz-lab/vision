# frozen_string_literal: true

module Ai
  class AssistantService
    MAX_TOOL_ROUNDS = 10

    def initialize(chat)
      @chat = chat
    end

    def send_message(user_content)
      @chat.assistant_messages.create!(role: :user, content: user_content)
      if @chat.title.blank?
        @chat.update!(title: user_content.truncate(60))
      end

      messages = build_messages
      tools = build_tools

      rounds = 0
      loop do
        rounds += 1
        response = call_claude(messages, tools)
        content_blocks = response["content"] || []
        text_parts = []
        tool_uses = []

        content_blocks.each do |block|
          case block["type"]
          when "text" then text_parts << block["text"]
          when "tool_use" then tool_uses << block
          end
        end

        if tool_uses.any?
          @chat.assistant_messages.create!(role: :tool_call, content: text_parts.join("\n").presence,
            metadata: { tool_calls: tool_uses.map { |tu| { id: tu["id"], name: tu["name"], input: tu["input"] } } })

          assistant_content = content_blocks.map { |b|
            case b["type"]
            when "text" then { type: "text", text: b["text"] }
            when "tool_use" then { type: "tool_use", id: b["id"], name: b["name"], input: b["input"] }
            end
          }.compact
          messages << { role: "assistant", content: assistant_content }

          tool_results_content = []
          tool_uses.each do |tu|
            result = execute_tool(tu["name"], tu["input"])
            @chat.assistant_messages.create!(role: :tool_result, content: result.to_json,
              metadata: { tool_use_id: tu["id"], tool_name: tu["name"] })
            tool_results_content << { type: "tool_result", tool_use_id: tu["id"], content: result.to_json }
          end
          messages << { role: "user", content: tool_results_content }
          break if rounds >= MAX_TOOL_ROUNDS
        else
          final_text = text_parts.join("\n")
          @chat.assistant_messages.create!(role: :assistant, content: final_text)
          return { role: "assistant", content: final_text }
        end
      end

      response = call_claude(messages, [])
      final_text = (response["content"] || []).select { |b| b["type"] == "text" }.map { |b| b["text"] }.join("\n")
      @chat.assistant_messages.create!(role: :assistant, content: final_text)
      { role: "assistant", content: final_text }
    rescue => e
      Rails.logger.error "[AssistantService] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_msg = "I encountered an error processing your request: #{e.message}"
      @chat.assistant_messages.create!(role: :assistant, content: error_msg)
      { role: "assistant", content: error_msg }
    end

    private

    def build_messages
      raw = @chat.assistant_messages.chronological.to_a
      messages = []
      raw.each do |msg|
        case msg.role
        when "user" then messages << { role: "user", content: msg.content }
        when "assistant" then messages << { role: "assistant", content: msg.content }
        when "tool_call"
          content = []
          content << { type: "text", text: msg.content } if msg.content.present?
          (msg.metadata["tool_calls"] || []).each do |tc|
            content << { type: "tool_use", id: tc["id"], name: tc["name"], input: tc["input"] }
          end
          messages << { role: "assistant", content: content }
        when "tool_result"
          block = { type: "tool_result", tool_use_id: msg.metadata["tool_use_id"], content: msg.content }
          if messages.last && messages.last[:role] == "user" && messages.last[:content].is_a?(Array)
            messages.last[:content] << block
          else
            messages << { role: "user", content: [ block ] }
          end
        end
      end
      messages
    end

    def build_tools
      Mcp::Server::TOOLS.map do |name, tool_class|
        { name: name, description: tool_class::DESCRIPTION, input_schema: tool_class::SCHEMA }
      end
    rescue => e
      Rails.logger.warn "[AssistantService] Could not load MCP tools: #{e.message}"
      []
    end

    def system_prompt
      "You are an AI assistant for Vision, the AI-powered image and document processing system. You help users manage AI tasks, analyze processing results, and configure vision pipelines."
    end

    def call_claude(messages, tools)
      client = Anthropic::Client.new
      params = { model: "claude-sonnet-4-20250514", max_tokens: 4096, system: system_prompt, messages: messages }
      params[:tools] = tools if tools.any?
      client.messages(parameters: params)
    end

    def execute_tool(name, arguments)
      tool_class = Mcp::Server::TOOLS[name]
      raise "Unknown tool: #{name}" unless tool_class
      tool = tool_class.new(nil)
      tool.call(arguments.symbolize_keys)
    rescue => e
      { error: e.message }
    end
  end
end
