require "rails_helper"

RSpec.describe "API::V1::Tasks", type: :request do
  let(:project) { create(:project) }
  let(:headers) { auth_headers(project) }

  before do
    allow(TaskExecutorJob).to receive(:perform_later)
  end

  describe "GET /api/v1/tasks" do
    let!(:pending_task)   { create(:ai_task, project: project, status: "pending") }
    let!(:running_task)   { create(:ai_task, :running,   project: project) }
    let!(:completed_task) { create(:ai_task, :completed, project: project) }

    it "returns all tasks for the project" do
      get "/api/v1/tasks", headers: headers
      body = JSON.parse(response.body)
      ids  = body["tasks"].map { |t| t["id"] }
      expect(ids).to include(pending_task.id, running_task.id, completed_task.id)
    end

    it "filters by status" do
      get "/api/v1/tasks", params: { status: "pending" }, headers: headers
      body = JSON.parse(response.body)
      ids  = body["tasks"].map { |t| t["id"] }
      expect(ids).to include(pending_task.id)
      expect(ids).not_to include(completed_task.id)
    end

    it "does not return tasks from other projects" do
      other      = create(:project)
      other_task = create(:ai_task, project: other)
      get "/api/v1/tasks", headers: headers
      body = JSON.parse(response.body)
      ids  = body["tasks"].map { |t| t["id"] }
      expect(ids).not_to include(other_task.id)
    end

    context "without authentication" do
      it "returns 401" do
        get "/api/v1/tasks"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/tasks" do
    let(:valid_params) do
      {
        instruction:      "Click the login button",
        start_url:        "https://example.com",
        model:            "claude-sonnet-4",
        browser_provider: "local",
        max_steps:        10,
        timeout_seconds:  120
      }
    end

    it "creates a new task and queues executor job" do
      expect {
        post "/api/v1/tasks", params: valid_params, headers: headers
      }.to change(AiTask, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(TaskExecutorJob).to have_received(:perform_later)
    end

    it "returns task in response" do
      post "/api/v1/tasks", params: valid_params, headers: headers
      body = JSON.parse(response.body)
      expect(body["instruction"]).to include("Click")
      expect(body["status"]).to eq("pending")
    end

    it "returns 422 for missing instruction" do
      post "/api/v1/tasks",
           params: { model: "claude-sonnet-4" },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/tasks/:id" do
    let!(:task) { create(:ai_task, :completed, project: project) }

    it "returns task details" do
      get "/api/v1/tasks/#{task.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(task.id)
      expect(body).to have_key("result")
      expect(body).to have_key("steps_executed")
    end

    it "returns 404 for unknown task" do
      get "/api/v1/tasks/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for task from another project" do
      other      = create(:project)
      other_task = create(:ai_task, project: other)
      get "/api/v1/tasks/#{other_task.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/tasks/:id/stop" do
    let!(:task) { create(:ai_task, :running, project: project) }

    it "requests stop for running task" do
      post "/api/v1/tasks/#{task.id}/stop", headers: headers
      expect(response).to have_http_status(:ok)
      expect(task.reload.stop_requested).to be true
    end

    it "returns 422 when task is not running" do
      completed = create(:ai_task, :completed, project: project)
      post "/api/v1/tasks/#{completed.id}/stop", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/tasks/:id/steps" do
    let!(:task)  { create(:ai_task, project: project) }
    let!(:step1) { create(:task_step, ai_task: task, position: 0) }
    let!(:step2) { create(:task_step, :navigate, ai_task: task, position: 1) }

    it "returns task steps in order" do
      get "/api/v1/tasks/#{task.id}/steps", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["steps"].size).to eq(2)
      expect(body["steps"].first["position"]).to eq(0)
    end
  end
end
