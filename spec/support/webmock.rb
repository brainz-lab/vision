require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.before(:each) do
    # Default stub for Platform API key validation
    stub_request(:post, /brainzlab_platform_url|platform:3000|localhost:3000/)
      .to_return(status: 200, body: { valid: false }.to_json, headers: { "Content-Type" => "application/json" })
  end
end
