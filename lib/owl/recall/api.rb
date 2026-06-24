# frozen_string_literal: true

require_relative '../result'
require_relative 'internal/tokenizer'
require_relative 'internal/corpus_builder'
require_relative 'internal/scorer'

module Owl
  # Cross-task memory: lexically recall similar tasks by their title + brief
  # (Problem/Goal). Pure Ruby, no network, no new gems. The corpus spans the
  # archive (`Owl::Archive::Api`), the active roster (`Owl::Tasks::Api` +
  # artifact/storage roles), or both, selected by `scope`.
  module Recall
    # Public facade for the recall engine. CLI/JSON/exit-code concerns live
    # in the CLI layer; this returns plain Ruby data.
    module Api
      DEFAULT_LIMIT = 10

      # Search areas the corpus can be built from. `archive` is the default
      # so existing callers (e.g. the orchestrator brief step) are unchanged.
      SCOPES = %w[active archive all].freeze

      module_function

      # Rank tasks in the requested `scope` against a free-text query.
      #
      # Returns an Array of `{ task_id:, title:, score:, snippet:, scope: }`
      # sorted by score descending then task_id ascending, truncated to
      # `limit`; each match carries `scope: 'active'|'archived'`. An
      # empty/stopword-only query, an empty corpus, or no matches all return
      # `[]`. A negative `limit` is clamped to `0` (returns `[]`) rather than
      # raising. An unknown `scope` returns an `Owl::Result::Err`
      # (`:invalid_scope`) instead of guessing.
      def recall(root:, query:, limit: DEFAULT_LIMIT, scope: 'archive')
        return invalid_scope(scope) unless SCOPES.include?(scope.to_s)

        capped = [limit.to_i, 0].max

        query_tokens = Internal::Tokenizer.tokens(query)
        return [] if query_tokens.empty?

        corpus = Internal::CorpusBuilder.build(root: root, scope: scope.to_s)
        return [] if corpus.empty?

        Internal::Scorer.rank(query_tokens: query_tokens, corpus: corpus, limit: capped)
      end

      def invalid_scope(scope)
        Owl::Result.err(
          code: :invalid_scope,
          message: "Unknown recall scope '#{scope}'; allowed: #{SCOPES.join(', ')}.",
          details: { scope: scope.to_s, allowed: SCOPES }
        )
      end
    end
  end
end
