# frozen_string_literal: true

require_relative 'tokenizer'

module Owl
  module Recall
    module Internal
      # tf-idf ranker over the recall corpus.
      #
      # Scores each document by the sum, over query terms it contains, of
      # `tf(term, doc) * idf(term)`, then length-normalizes by the square
      # root of the document token count so short titles do not unfairly
      # dominate long briefs. Pure and deterministic: ties on score break by
      # `task_id` ascending. Snippets are a single ~140-char whitespace-
      # collapsed line, safe to embed in a JSON string.
      module Scorer
        SNIPPET_MAX = 140
        ELLIPSIS = '...'

        module_function

        def rank(query_tokens:, corpus:, limit:)
          return [] if query_tokens.empty? || corpus.empty?

          query = query_tokens.uniq
          docs = corpus.map { |doc| prepare(doc) }
          idf = compute_idf(docs)

          scored = docs.filter_map { |doc| score_doc(doc, query, idf) }
          scored.sort_by { |match| [-match[:score], match[:task_id]] }.first(limit)
        end

        def prepare(doc)
          tokens = Tokenizer.tokens(doc[:text])
          { task_id: doc[:task_id], title: doc[:title].to_s, text: doc[:text].to_s,
            counts: tokens.tally, length: tokens.length }
        end

        # idf with add-one smoothing: ln((1 + N) / (1 + df)) + 1.
        def compute_idf(docs)
          total = docs.length
          doc_freq = Hash.new(0)
          docs.each { |doc| doc[:counts].each_key { |term| doc_freq[term] += 1 } }
          doc_freq.transform_values { |df| Math.log((1.0 + total) / (1.0 + df)) + 1.0 }
        end

        def score_doc(doc, query, idf)
          raw = query.sum do |term|
            tf = doc[:counts].fetch(term, 0)
            tf.zero? ? 0.0 : tf * idf.fetch(term, 0.0)
          end
          return nil if raw <= 0.0

          score = doc[:length].zero? ? 0.0 : raw / Math.sqrt(doc[:length])
          { task_id: doc[:task_id], title: doc[:title], score: score.round(6),
            snippet: snippet(doc, query) }
        end

        def snippet(doc, query)
          line = matching_line(doc[:text], query) || doc[:title]
          truncate(collapse(line))
        end

        def matching_line(text, query)
          text.each_line.map(&:strip).reject(&:empty?).find do |line|
            Tokenizer.tokens(line).any? { |token| query.include?(token) }
          end
        end

        def collapse(string)
          string.to_s.gsub(/\s+/, ' ').strip
        end

        def truncate(string)
          return string if string.length <= SNIPPET_MAX

          "#{string[0, SNIPPET_MAX - ELLIPSIS.length].rstrip}#{ELLIPSIS}"
        end
      end
    end
  end
end
