require "rails_helper"

RSpec.describe BrowserSession, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to have_one(:ai_task) }
  end

  describe "validations" do
    subject { build(:browser_session) }

    it { is_expected.to validate_presence_of(:provider_session_id) }
    it { is_expected.to validate_uniqueness_of(:provider_session_id) }
    it { is_expected.to validate_presence_of(:browser_provider) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:browser_provider).in_array(BrowserSession::PROVIDERS) }
    it { is_expected.to validate_inclusion_of(:status).in_array(BrowserSession::STATUSES) }
  end

  describe "scopes" do
    let(:project) { create(:project) }
    let!(:active_session)  { create(:browser_session, project: project, status: "active") }
    let!(:idle_session)    { create(:browser_session, project: project, status: "idle") }
    let!(:closed_session)  { create(:browser_session, :closed, project: project) }
    let!(:expired_session) { create(:browser_session, :expired, project: project) }
    let!(:cloud_session)   { create(:browser_session, :cloud, project: project) }

    it ".active returns initializing/active/idle sessions" do
      expect(BrowserSession.active).to include(active_session, idle_session)
      expect(BrowserSession.active).not_to include(closed_session)
    end

    it ".closed returns closed sessions" do
      expect(BrowserSession.closed).to include(closed_session)
      expect(BrowserSession.closed).not_to include(active_session)
    end

    it ".expired returns expired sessions" do
      expect(BrowserSession.expired).to include(expired_session)
      expect(BrowserSession.expired).not_to include(active_session)
    end

    it ".by_provider filters by provider" do
      expect(BrowserSession.by_provider("hyperbrowser")).to include(cloud_session)
      expect(BrowserSession.by_provider("local")).to include(active_session)
    end
  end

  describe "status predicates" do
    it "returns correct predicates" do
      expect(build(:browser_session, status: "initializing").initializing?).to be true
      expect(build(:browser_session, status: "active").active?).to be true
      expect(build(:browser_session, status: "idle").idle?).to be true
      expect(build(:browser_session, :error).errored?).to be true
      expect(build(:browser_session, :closed).closed?).to be true
    end

    it "#alive? returns true for non-closed states" do
      expect(build(:browser_session, status: "active").alive?).to be true
      expect(build(:browser_session, status: "idle").alive?).to be true
      expect(build(:browser_session, :closed).alive?).to be false
    end

    it "#expired? returns true when expires_at is in the past" do
      session = build(:browser_session, :expired)
      expect(session.expired?).to be true
    end

    it "#expired? returns false when expires_at is in the future" do
      session = build(:browser_session, expires_at: 1.hour.from_now)
      expect(session.expired?).to be false
    end
  end

  describe "provider predicates" do
    BrowserSession::PROVIDERS.each do |provider|
      it "#{provider}? returns true when browser_provider is #{provider}" do
        session = build(:browser_session, browser_provider: provider)
        expect(session.public_send("#{provider}?")).to be true
      end
    end

    it "#cloud? returns false for local provider" do
      session = build(:browser_session, browser_provider: "local")
      expect(session.cloud?).to be false
    end

    it "#cloud? returns true for non-local provider" do
      session = build(:browser_session, :cloud)
      expect(session.cloud?).to be true
    end
  end

  describe "state transitions" do
    let(:project) { create(:project) }

    describe "#activate!" do
      it "sets status to active" do
        session = create(:browser_session, project: project, status: "initializing")
        session.activate!
        expect(session.reload.status).to eq("active")
      end
    end

    describe "#mark_idle!" do
      it "sets status to idle" do
        session = create(:browser_session, project: project, status: "active")
        session.mark_idle!
        expect(session.reload.status).to eq("idle")
      end
    end

    describe "#mark_error!" do
      it "sets status to error with message in metadata" do
        session = create(:browser_session, project: project, metadata: {})
        session.mark_error!("Connection dropped")
        session.reload
        expect(session.status).to eq("error")
        expect(session.metadata["error"]).to eq("Connection dropped")
      end
    end

    describe "#close!" do
      it "sets status to closed with closed_at timestamp" do
        session = create(:browser_session, project: project)
        session.close!
        session.reload
        expect(session.status).to eq("closed")
        expect(session.closed_at).to be_within(2.seconds).of(Time.current)
      end
    end

    describe "#update_state!" do
      it "updates current url and title" do
        session = create(:browser_session, project: project)
        session.update_state!(url: "https://example.com", title: "Home")
        session.reload
        expect(session.current_url).to eq("https://example.com")
        expect(session.current_title).to eq("Home")
        expect(session.status).to eq("active")
      end
    end
  end

  describe "#extend_expiry!" do
    it "extends expires_at by given duration" do
      project = create(:project)
      session = create(:browser_session, project: project, expires_at: 1.minute.from_now)
      session.extend_expiry!(1.hour)
      expect(session.reload.expires_at).to be_within(5.seconds).of(1.hour.from_now)
    end
  end

  describe "#info" do
    it "returns summary hash with expected keys" do
      session = build(:browser_session)
      info = session.info
      expect(info).to have_key(:id)
      expect(info).to have_key(:status)
      expect(info).to have_key(:browser_provider)
      expect(info).to have_key(:viewport)
    end
  end

  describe "defaults" do
    it "sets defaults on create" do
      project = create(:project)
      session = BrowserSession.create!(
        project: project,
        provider_session_id: "sess_#{SecureRandom.hex(8)}"
      )
      expect(session.status).to eq("initializing")
      expect(session.browser_provider).to eq("local")
      expect(session.expires_at).to be_within(35.minutes).of(Time.current)
    end
  end
end
