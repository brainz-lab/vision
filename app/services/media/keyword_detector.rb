# frozen_string_literal: true

module Media
  class KeywordDetector
    DEFAULT_WEIGHT = 15
    MAX_SCORE = 100

    # Trailing characters stripped to produce a match stem for single-word keywords.
    # This allows "arreglo" to match "arreglar", "arreglaron", etc. (Spanish inflections).
    STEM_STRIP_PATTERN = /[aeiouáéíóú]+\z/i

    attr_reader :segments, :keywords, :weights

    def initialize(segments, keywords:, weights: {})
      @segments = segments
      @keywords = keywords.map(&:downcase)
      @weights = weights.transform_keys(&:downcase)
    end

    def detect
      matches = find_matches
      score = calculate_score(matches)

      {
        matches: matches,
        score: [ score, MAX_SCORE ].min,
        keywords_searched: keywords,
        total_segments: segments.length
      }
    end

    private

    def find_matches
      matches = []

      segments.each do |segment|
        text_lower = segment[:text].downcase

        keywords.each do |keyword|
          pattern = build_pattern(keyword)

          text_lower.scan(pattern).each do |matched_text|
            matches << {
              keyword: matched_text.strip,
              timestamp: segment[:start],
              segment_end: segment[:end],
              context: segment[:text]
            }
          end
        end
      end

      matches
    end

    # Build a regex pattern for a keyword.
    #
    # - Multi-word phrases: exact match (case-insensitive).
    # - Single words: strip trailing vowels to form a stem, then match any word
    #   starting with that stem. This handles Spanish inflections, e.g.:
    #     "arreglo" → stem "arregl" → matches "arreglar", "arreglo", "arreglaron"
    #     "plata"   → stem "plat"  → matches "plata", "platas"
    #   If stripping vowels would leave an empty stem (e.g. a single-vowel keyword),
    #   fall back to matching the keyword verbatim.
    def build_pattern(keyword)
      if keyword.include?(" ")
        /#{Regexp.escape(keyword)}/i
      else
        stem = keyword.sub(STEM_STRIP_PATTERN, "")
        stem = keyword if stem.empty?
        /\b#{Regexp.escape(stem)}\w*/i
      end
    end

    def calculate_score(matches)
      return 0 if matches.empty?

      total = matches.sum do |match|
        matched_word = match[:keyword].downcase
        # Find which original keyword this match belongs to by checking if the
        # matched word starts with that keyword's stem.
        weight_key = keywords.find do |kw|
          stem = kw.sub(STEM_STRIP_PATTERN, "")
          stem = kw if stem.empty?
          matched_word.start_with?(stem)
        end || matched_word
        weights.fetch(weight_key, DEFAULT_WEIGHT)
      end

      total
    end
  end
end
