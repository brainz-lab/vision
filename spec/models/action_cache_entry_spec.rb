require "rails_helper"

RSpec.describe ActionCacheEntry, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:project) }
  end

  describe "validations" do
    subject { build(:action_cache_entry) }

    it { is_expected.to validate_presence_of(:url_pattern) }
    it { is_expected.to validate_presence_of(:action_type) }
    it { is_expected.to validate_presence_of(:action_data) }
    it { is_expected.to validate_inclusion_of(:action_type).in_array(ActionCacheEntry::CACHEABLE_ACTIONS) }
  end

  describe "scopes" do
    let(:project) { create(:project) }
    let!(:active_entry)   { create(:action_cache_entry, project: project) }
    let!(:expired_entry)  { create(:action_cache_entry, :expired, project: project) }
    let!(:reliable_entry) { create(:action_cache_entry, project: project, success_count: 10, failure_count: 0) }
    let!(:unreliable_entry) { create(:action_cache_entry, :unreliable, project: project) }

    it ".active returns non-expired entries" do
      expect(ActionCacheEntry.active).to include(active_entry, reliable_entry)
      expect(ActionCacheEntry.active).not_to include(expired_entry)
    end

    it ".expired returns expired entries" do
      expect(ActionCacheEntry.expired).to include(expired_entry)
      expect(ActionCacheEntry.expired).not_to include(active_entry)
    end

    it ".reliable returns entries where success > failure * 2" do
      expect(ActionCacheEntry.reliable).to include(active_entry, reliable_entry)
      expect(ActionCacheEntry.reliable).not_to include(unreliable_entry)
    end

    it ".most_used orders by success_count desc" do
      expect(ActionCacheEntry.most_used.first).to eq(reliable_entry)
    end
  end

  describe ".url_to_pattern" do
    it "returns host and path without query params" do
      result = ActionCacheEntry.url_to_pattern("https://example.com/dashboard?tab=main")
      expect(result).to eq("example.com/dashboard")
    end

    it "returns original url when already a pattern (contains %)" do
      result = ActionCacheEntry.url_to_pattern("example.com%")
      expect(result).to eq("example.com%")
    end
  end

  describe ".store" do
    let(:project) { create(:project) }

    it "creates a new cache entry" do
      expect {
        ActionCacheEntry.store(
          project: project,
          url: "https://example.com/login",
          action: "click",
          action_data: { selector: "button.login" }
        )
      }.to change(ActionCacheEntry, :count).by(1)
    end

    it "increments success_count for existing entry" do
      ActionCacheEntry.store(project: project, url: "https://example.com/login", action: "click", action_data: { selector: "btn" })
      entry = ActionCacheEntry.store(project: project, url: "https://example.com/login", action: "click", action_data: { selector: "btn" })
      expect(entry.success_count).to eq(2)
    end
  end

  describe ".lookup" do
    let(:project) { create(:project) }

    it "returns nil when no matching entry" do
      expect(ActionCacheEntry.lookup(project: project, url: "https://unknown.com")).to be_nil
    end

    it "returns reliable entry for matching url and action" do
      entry = create(:action_cache_entry, project: project, url_pattern: "example.com/dashboard", action_type: "click", success_count: 10, failure_count: 0)
      result = ActionCacheEntry.lookup(project: project, url: "https://example.com/dashboard", action_type: "click")
      expect(result).to eq(entry)
    end
  end

  describe ".cleanup_expired!" do
    let(:project) { create(:project) }
    let!(:expired_entry) { create(:action_cache_entry, :expired, project: project) }
    let!(:active_entry)  { create(:action_cache_entry, project: project) }

    it "deletes expired entries" do
      expect { ActionCacheEntry.cleanup_expired! }.to change(ActionCacheEntry, :count).by(-1)
      expect(ActionCacheEntry.find_by(id: active_entry.id)).to be_present
    end
  end

  describe "#record_success!" do
    it "increments success_count and updates last_used_at" do
      project = create(:project)
      entry   = create(:action_cache_entry, project: project, success_count: 3)
      entry.record_success!(duration_ms: 200)
      entry.reload
      expect(entry.success_count).to eq(4)
      expect(entry.last_used_at).to be_within(2.seconds).of(Time.current)
    end

    it "calculates rolling avg_duration_ms" do
      project = create(:project)
      entry   = create(:action_cache_entry, project: project, success_count: 4, avg_duration_ms: 100.0)
      entry.record_success!(duration_ms: 200)
      expect(entry.avg_duration_ms).to be_within(1).of(120.0)
    end
  end

  describe "#record_failure!" do
    it "increments failure_count" do
      project = create(:project)
      entry   = create(:action_cache_entry, project: project, success_count: 2, failure_count: 0)
      entry.record_failure!
      expect(entry.reload.failure_count).to eq(1)
    end

    it "invalidates entry when failure threshold reached" do
      project = create(:project)
      entry   = create(:action_cache_entry, project: project, success_count: 1, failure_count: 3)
      expect { entry.record_failure! }.to change(ActionCacheEntry, :count).by(-1)
    end
  end

  describe "#reliable?" do
    it "returns true when success_count > failure_count * 2" do
      entry = build(:action_cache_entry, success_count: 10, failure_count: 2)
      expect(entry.reliable?).to be true
    end

    it "returns false when too many failures" do
      entry = build(:action_cache_entry, :unreliable)
      expect(entry.reliable?).to be false
    end
  end

  describe "#success_rate" do
    it "returns 100 when no failures" do
      entry = build(:action_cache_entry, success_count: 5, failure_count: 0)
      expect(entry.success_rate).to eq(100.0)
    end

    it "calculates correct rate" do
      entry = build(:action_cache_entry, success_count: 8, failure_count: 2)
      expect(entry.success_rate).to eq(80.0)
    end

    it "returns 100 when total is zero" do
      entry = build(:action_cache_entry, success_count: 0, failure_count: 0)
      expect(entry.success_rate).to eq(100.0)
    end
  end
end
