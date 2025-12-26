module Mcp
  module Tools
    class Base
      DESCRIPTION = "Base tool class"
      SCHEMA = {
        type: 'object',
        properties: {}
      }.freeze

      attr_reader :project

      def initialize(project)
        @project = project
      end

      def call(args)
        raise NotImplementedError, "Subclasses must implement #call"
      end

      protected

      def success(data)
        { success: true, data: data }
      end

      def error(message)
        { success: false, error: message }
      end
    end
  end
end
