FactoryBot.define do
  factory :media_analysis do
    project
    analysis_type { "transcribe" }
    status { "pending" }
    source_url { "https://s3.example.com/recordings/test-audio.webm" }
    parameters { {} }
    result { {} }

    trait :processing do
      status { "processing" }
    end

    trait :completed do
      status { "completed" }
      duration_ms { 2500 }
    end

    trait :error do
      status { "error" }
      error_message { "Processing failed" }
    end

    trait :transcription do
      analysis_type { "transcribe" }
      parameters { { language: "es" } }
    end

    trait :keyword_detection do
      analysis_type { "detect_keywords" }
      parameters { { keywords: ["plata", "arreglo", "no reportar"] } }
    end

    trait :frame_extraction do
      analysis_type { "extract_frames" }
      parameters { { interval_seconds: 60 } }
    end

    trait :video_analysis do
      analysis_type { "analyze_video" }
      parameters { { prompt: "Count equipment installed" } }
    end
  end
end
