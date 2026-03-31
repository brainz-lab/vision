require "rails_helper"

RSpec.describe Media::KeywordDetector do
  let(:segments) do
    [
      { start: "00:00:00.000", end: "00:00:05.000", text: "Buenos dias, vengo a revisar el medidor." },
      { start: "00:00:05.000", end: "00:00:10.000", text: "Ingeniero, no hay forma de arreglar esto sin el reporte?" },
      { start: "00:00:10.000", end: "00:00:15.000", text: "Le puedo dar plata si no reporta nada." },
      { start: "00:00:15.000", end: "00:00:20.000", text: "Dejeme ver que puedo hacer." }
    ]
  end

  let(:keywords) { [ "plata", "arreglo", "no reportar", "no reporta", "entre nosotros", "colaboracion" ] }

  describe "#detect" do
    it "returns matches with timestamps and context" do
      detector = described_class.new(segments, keywords: keywords)
      result = detector.detect

      expect(result[:matches]).to be_an(Array)
      expect(result[:matches].length).to be >= 3
      expect(result[:matches].map { |m| m[:keyword] }).to include("plata")
      expect(result[:matches].map { |m| m[:keyword] }).to include("arreglar")
    end

    it "calculates a fraud score" do
      detector = described_class.new(segments, keywords: keywords)
      result = detector.detect

      expect(result[:score]).to be_a(Numeric)
      expect(result[:score]).to be > 0
      expect(result[:score]).to be <= 100
    end

    it "includes the timestamp of each match" do
      detector = described_class.new(segments, keywords: keywords)
      result = detector.detect

      plata_match = result[:matches].find { |m| m[:keyword] == "plata" }
      expect(plata_match).not_to be_nil
      expect(plata_match[:timestamp]).to eq("00:00:10.000")
      expect(plata_match[:context]).to include("plata")
    end

    context "when no keywords found" do
      let(:clean_segments) do
        [
          { start: "00:00:00.000", end: "00:00:05.000", text: "Buenos dias, el medidor esta funcionando bien." },
          { start: "00:00:05.000", end: "00:00:10.000", text: "Gracias por su tiempo." }
        ]
      end

      it "returns empty matches and zero score" do
        detector = described_class.new(clean_segments, keywords: keywords)
        result = detector.detect

        expect(result[:matches]).to be_empty
        expect(result[:score]).to eq(0)
      end
    end

    context "with custom weights" do
      it "applies weights to score calculation" do
        weights = { "plata" => 40, "arreglo" => 25, "no reporta" => 35 }
        detector = described_class.new(segments, keywords: keywords, weights: weights)
        result = detector.detect

        expect(result[:score]).to be > 50
      end
    end
  end
end
