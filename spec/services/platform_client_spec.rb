require "rails_helper"

RSpec.describe PlatformClient do
  let(:platform_url) { "http://platform:3000" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("BRAINZLAB_PLATFORM_URL").and_return(platform_url)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("BRAINZLAB_PLATFORM_URL", anything).and_return(platform_url)

    Rails.cache.clear
  end

  describe ".validate_key" do
    context "with blank key" do
      it "returns invalid response without HTTP call" do
        result = PlatformClient.validate_key(nil)
        expect(result[:valid]).to be false

        result = PlatformClient.validate_key("")
        expect(result[:valid]).to be false
      end
    end

    context "with valid key" do
      before do
        stub_request(:post, "#{platform_url}/api/v1/keys/validate")
          .to_return(
            status: 200,
            body: {
              valid: true,
              project_id: "proj_123",
              project_name: "Test Project",
              environment: "production",
              features: { vision: true }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns valid response with project info" do
        result = PlatformClient.validate_key("vis_api_abc123")
        expect(result[:valid]).to be true
        expect(result[:project_id]).to eq("proj_123")
        expect(result[:project_name]).to eq("Test Project")
        expect(result[:features]).to include(vision: true)
      end
    end

    context "with invalid key" do
      before do
        stub_request(:post, "#{platform_url}/api/v1/keys/validate")
          .to_return(
            status: 200,
            body: { valid: false }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns invalid response" do
        result = PlatformClient.validate_key("invalid_key")
        expect(result[:valid]).to be false
      end
    end

    context "caching" do
      before do
        stub_request(:post, "#{platform_url}/api/v1/keys/validate")
          .to_return(
            status: 200,
            body: { valid: true, project_id: "proj_1", project_name: "P", environment: "test", features: { vision: true } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "only makes one HTTP call for repeated requests with same key" do
        PlatformClient.validate_key("vis_api_same_key")
        PlatformClient.validate_key("vis_api_same_key")

        expect(WebMock).to have_requested(:post, "#{platform_url}/api/v1/keys/validate").once
      end
    end

    context "when platform is unreachable" do
      before do
        stub_request(:post, "#{platform_url}/api/v1/keys/validate")
          .to_raise(Errno::ECONNREFUSED)
      end

      around do |example|
        original = Rails.env
        # Force test env to behave like production (not development bypass)
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))
        example.run
      end

      it "returns invalid response" do
        result = PlatformClient.validate_key("some_key")
        expect(result[:valid]).to be false
      end
    end
  end
end
