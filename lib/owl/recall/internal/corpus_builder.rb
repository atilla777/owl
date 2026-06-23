# frozen_string_literal: true

require_relative '../../archive/api'

module Owl
  module Recall
    module Internal
      # Builds the recall search corpus from the archive role.
      #
      # The corpus is exactly the set of archived tasks. Each document is
      # `{ task_id:, title:, text: }`, where `text` is the task title plus
      # the `Problem` and `Goal` sections of its `brief` artifact (when one
      # exists). All corpus reads go through `Owl::Archive::Api` (`list` /
      # `read`) — never a direct `File.read` — so the Backend/Internal/Api
      # layering and source-of-truth invariants hold (docs/agents/27).
      module CorpusBuilder
        # Heading names (case-folded) whose section bodies feed the corpus.
        # Matched at any heading level so both legacy `# Problem` and newer
        # `## Problem` briefs are picked up.
        TARGET_SECTIONS = %w[problem goal].freeze

        HEADING_PATTERN = /\A#+\s+(.+?)\s*\z/

        module_function

        def build(root:)
          listing = Owl::Archive::Api.list(root: root)
          return [] if listing.err?

          listing.value[:archived].map { |entry| document(root: root, entry: entry) }
        end

        def document(root:, entry:)
          title = entry[:title].to_s
          brief_text = extract_brief(root: root, task_id: entry[:task_id])
          text = brief_text.empty? ? title : "#{title} #{brief_text}"
          { task_id: entry[:task_id], title: title, text: text }
        end

        def extract_brief(root:, task_id:)
          result = Owl::Archive::Api.read(root: root, task_id: task_id, artifact_key: 'brief')
          return '' if result.err?

          extract_sections(result.value[:body])
        end

        # Collect prose under the target headings, stopping at the next
        # heading that is not itself a target section.
        def extract_sections(body)
          return '' if body.to_s.strip.empty?

          collected = []
          capturing = false
          body.each_line do |line|
            heading = line.match(HEADING_PATTERN)
            if heading
              capturing = TARGET_SECTIONS.include?(heading[1].downcase)
              next
            end
            stripped = line.strip
            collected << stripped if capturing && !stripped.empty?
          end
          collected.join(' ')
        end
      end
    end
  end
end
