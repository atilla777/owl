# frozen_string_literal: true

module Owl
  module Recall
    module Internal
      # Pure, stateless lexical tokenizer for the recall engine.
      #
      # Splits a string into normalized word tokens: Unicode-aware
      # case-folding (`String#downcase` applies full Unicode case mapping,
      # so Cyrillic folds correctly), splitting on runs of letters/digits
      # (`\p{L}\p{N}`), and dropping empties plus a short built-in ru/en
      # stopword list. No I/O, no state — deterministic for a given input.
      module Tokenizer
        # Short ru/en stopword list. Kept intentionally small: enough to
        # drop the highest-frequency function words that add noise to
        # token-overlap scoring, without trimming domain vocabulary.
        STOPWORDS = %w[
          a an and are as at be but by for from has have if in into is it its of
          on or that the their then there these this to was were will with
          в во и из или к как на не нет но о об от по с со та так те то у уже
          что чтобы это эта эти этот для же бы ли а
        ].freeze

        WORD_PATTERN = /[\p{L}\p{N}]+/

        module_function

        def tokens(string)
          return [] if string.nil?

          string.downcase.scan(WORD_PATTERN).reject do |token|
            token.empty? || STOPWORDS.include?(token)
          end
        end
      end
    end
  end
end
