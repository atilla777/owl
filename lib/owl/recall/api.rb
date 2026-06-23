# frozen_string_literal: true

require_relative 'internal/tokenizer'
require_relative 'internal/corpus_builder'
require_relative 'internal/scorer'

module Owl
  # Cross-task memory: lexically recall similar ARCHIVED tasks by their
  # title + brief (Problem/Goal). Pure Ruby, no network, no new gems. The
  # corpus is read only through `Owl::Archive::Api` (the archive role).
  module Recall
    # Public facade for the recall engine. CLI/JSON/exit-code concerns live
    # in the CLI layer; this returns plain Ruby data.
    module Api
      DEFAULT_LIMIT = 10

      module_function

      # Rank archived tasks against a free-text query.
      #
      # Returns an Array of `{ task_id:, title:, score:, snippet: }` sorted
      # by score descending then task_id ascending, truncated to `limit`.
      # An empty/stopword-only query, an empty archive, or no matches all
      # return `[]`. A negative `limit` is clamped to `0` (returns `[]`)
      # rather than raising, so the command never crashes on bad input.
      def recall(root:, query:, limit: DEFAULT_LIMIT)
        capped = [limit.to_i, 0].max

        query_tokens = Internal::Tokenizer.tokens(query)
        return [] if query_tokens.empty?

        corpus = Internal::CorpusBuilder.build(root: root)
        return [] if corpus.empty?

        Internal::Scorer.rank(query_tokens: query_tokens, corpus: corpus, limit: capped)
      end
    end
  end
end
