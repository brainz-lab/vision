require "rails_helper"

RSpec.describe ComparisonService do
  let(:project)        { create(:project) }
  let(:page)           { create(:page, project: project) }
  let(:browser_config) { create(:browser_config, project: project) }
  let(:baseline)       { create(:baseline, page: page, browser_config: browser_config) }
  let(:snapshot)       { create(:snapshot, :captured, page: page, browser_config: browser_config) }

  let(:fake_image_data) { "fake_png_data" }

  before do
    allow(baseline).to receive_message_chain(:screenshot, :attached?).and_return(true)
    allow(baseline).to receive_message_chain(:screenshot, :download).and_return(fake_image_data)
    allow(snapshot).to receive_message_chain(:screenshot, :attached?).and_return(true)
    allow(snapshot).to receive_message_chain(:screenshot, :download).and_return(fake_image_data)
  end

  describe "#compare" do
    context "when images match within threshold" do
      before do
        allow(DiffService).to receive(:new).and_return(
          double(diff: { diff_percentage: 0.0, diff_pixels: 0, diff_image: nil })
        )
      end

      it "creates a passed comparison" do
        service    = ComparisonService.new(baseline, snapshot)
        comparison = service.compare
        expect(comparison.status).to eq("passed")
        expect(comparison.diff_percentage).to eq(0.0)
      end

      it "marks snapshot as compared" do
        service = ComparisonService.new(baseline, snapshot)
        service.compare
        expect(snapshot.reload.status).to eq("compared")
      end
    end

    context "when images differ beyond threshold" do
      before do
        allow(DiffService).to receive(:new).and_return(
          double(diff: { diff_percentage: 5.0, diff_pixels: 2000, diff_image: nil })
        )
      end

      it "creates a failed comparison with pending review" do
        service    = ComparisonService.new(baseline, snapshot)
        comparison = service.compare
        expect(comparison.status).to eq("failed")
        expect(comparison.review_status).to eq("pending")
        expect(comparison.diff_percentage).to eq(5.0)
      end
    end

    context "when using custom threshold" do
      before do
        allow(DiffService).to receive(:new).and_return(
          double(diff: { diff_percentage: 3.0, diff_pixels: 500, diff_image: nil })
        )
      end

      it "passes when diff is within custom threshold" do
        service    = ComparisonService.new(baseline, snapshot, threshold: 0.05)
        comparison = service.compare
        expect(comparison.status).to eq("passed")
      end

      it "fails when diff exceeds custom threshold" do
        service    = ComparisonService.new(baseline, snapshot, threshold: 0.01)
        comparison = service.compare
        expect(comparison.status).to eq("failed")
      end
    end

    context "when test_run is associated" do
      let(:test_run) do
        create(:test_run, project: project, status: "running",
               total_pages: 1, passed_count: 0, failed_count: 0, error_count: 0)
      end
      let(:snapshot_with_run) do
        create(:snapshot, :captured, page: page, browser_config: browser_config, test_run: test_run)
      end

      before do
        allow(snapshot_with_run).to receive_message_chain(:screenshot, :attached?).and_return(true)
        allow(snapshot_with_run).to receive_message_chain(:screenshot, :download).and_return(fake_image_data)
        allow(DiffService).to receive(:new).and_return(
          double(diff: { diff_percentage: 0.0, diff_pixels: 0, diff_image: nil })
        )
      end

      it "increments test run passed_count on pass" do
        service = ComparisonService.new(baseline, snapshot_with_run)
        service.compare
        expect(test_run.reload.passed_count).to eq(1)
      end
    end

    context "when DiffService raises an error" do
      before do
        allow(DiffService).to receive(:new).and_raise(RuntimeError, "ImageMagick failed")
      end

      it "creates an error comparison" do
        service    = ComparisonService.new(baseline, snapshot)
        comparison = service.compare
        expect(comparison.status).to eq("error")
      end

      it "marks snapshot as error" do
        service = ComparisonService.new(baseline, snapshot)
        service.compare
        expect(snapshot.reload.status).to eq("error")
      end
    end

    context "when baseline has no screenshot" do
      before do
        allow(baseline).to receive_message_chain(:screenshot, :attached?).and_return(false)
      end

      it "creates an error comparison" do
        service    = ComparisonService.new(baseline, snapshot)
        comparison = service.compare
        expect(comparison.status).to eq("error")
      end
    end
  end
end
