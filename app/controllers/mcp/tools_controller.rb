module Mcp
  class ToolsController < ActionController::API
    before_action :authenticate!

    # GET /mcp/tools
    def index
      render json: {
        tools: Mcp::Server::TOOLS.map do |name, tool_class|
          {
            name: name,
            description: tool_class::DESCRIPTION,
            inputSchema: tool_class::SCHEMA
          }
        end
      }
    end

    # POST /mcp/tools/:name
    def call
      tool_name = params[:name]
      tool_class = Mcp::Server::TOOLS[tool_name]

      unless tool_class
        render json: { error: "Unknown tool: #{tool_name}" }, status: :not_found
        return
      end

      tool = tool_class.new(@current_project)
      result = tool.call(tool_params)

      render json: result
    rescue => e
      Rails.logger.error "MCP tool #{tool_name} failed: #{e.message}"
      render json: { error: e.message }, status: :internal_server_error
    end

    # POST /mcp/rpc
    # JSON-RPC compatible endpoint
    def rpc
      method = params[:method]
      tool_name = method&.gsub('tools/', '')

      case params[:method]
      when 'tools/list'
        render json: {
          jsonrpc: '2.0',
          id: params[:id],
          result: {
            tools: Mcp::Server::TOOLS.map do |name, tool_class|
              {
                name: name,
                description: tool_class::DESCRIPTION,
                inputSchema: tool_class::SCHEMA
              }
            end
          }
        }
      when /^tools\/call/
        tool_name = params.dig(:params, :name)
        tool_class = Mcp::Server::TOOLS[tool_name]

        unless tool_class
          render json: {
            jsonrpc: '2.0',
            id: params[:id],
            error: { code: -32601, message: "Unknown tool: #{tool_name}" }
          }
          return
        end

        tool = tool_class.new(@current_project)
        arguments = params.dig(:params, :arguments) || {}
        result = tool.call(arguments.to_unsafe_h.symbolize_keys)

        render json: {
          jsonrpc: '2.0',
          id: params[:id],
          result: { content: [{ type: 'text', text: result.to_json }] }
        }
      else
        render json: {
          jsonrpc: '2.0',
          id: params[:id],
          error: { code: -32601, message: "Unknown method: #{params[:method]}" }
        }
      end
    rescue => e
      render json: {
        jsonrpc: '2.0',
        id: params[:id],
        error: { code: -32603, message: e.message }
      }
    end

    private

    def authenticate!
      raw_key = extract_api_key
      key_info = PlatformClient.validate_key(raw_key)

      unless key_info[:valid]
        render json: { error: 'Invalid API key' }, status: :unauthorized
        return
      end

      @current_project = Project.find_or_create_for_platform!(
        platform_project_id: key_info[:project_id],
        name: key_info[:project_name],
        environment: key_info[:environment]
      )
    end

    def extract_api_key
      auth_header = request.headers['Authorization']
      return auth_header.sub(/^Bearer\s+/, '') if auth_header&.start_with?('Bearer ')
      request.headers['X-API-Key'] || params[:api_key]
    end

    def tool_params
      params.except(:controller, :action, :name, :format).to_unsafe_h.symbolize_keys
    end
  end
end
