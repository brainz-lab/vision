module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_project_id

    def connect
      self.current_project_id = find_project_id
    end

    private

    def find_project_id
      # Accept project_id from query params for API clients
      request.params[:project_id]
    end
  end
end
