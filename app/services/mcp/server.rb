module Mcp
  class Server
    TOOLS = {
      # Visual regression testing tools
      "vision_capture" => Tools::VisionCapture,
      "vision_compare" => Tools::VisionCompare,
      "vision_test" => Tools::VisionTest,
      "vision_approve" => Tools::VisionApprove,
      "vision_list_failures" => Tools::VisionListFailures,

      # AI browser automation tools
      "vision_task" => Tools::VisionTask,
      "vision_agent" => Tools::VisionAgent,  # Conversational agent with step-by-step reasoning
      "vision_ai_action" => Tools::VisionAiAction,
      "vision_perform" => Tools::VisionPerform,
      "vision_extract" => Tools::VisionExtract,

      # Credential management (Vault integration)
      "vision_credential" => Tools::VisionCredential
    }.freeze

    attr_reader :project

    def initialize(project)
      @project = project
    end

    def list_tools
      TOOLS.map do |name, tool_class|
        {
          name: name,
          description: tool_class::DESCRIPTION,
          inputSchema: tool_class::SCHEMA
        }
      end
    end

    def call_tool(name, arguments)
      tool_class = TOOLS[name]
      raise "Unknown tool: #{name}" unless tool_class

      tool = tool_class.new(@project)
      tool.call(arguments.symbolize_keys)
    end
  end
end
