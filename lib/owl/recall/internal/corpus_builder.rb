# frozen_string_literal: true

require_relative '../../archive/api'
require_relative '../../tasks/api'
require_relative '../../artifacts/api'
require_relative '../../storage/api'

module Owl
  module Recall
    module Internal
      # Builds the recall search corpus for a requested scope.
      #
      # Each document is `{ task_id:, title:, text:, scope: }`, where `text`
      # is the task title plus the `Problem` and `Goal` sections of its
      # `brief` artifact (when one exists) and `scope` is `'archived'` or
      # `'active'`.
      #
      # - `archive` (default) — the set of archived tasks, read through
      #   `Owl::Archive::Api` (`list` / `read`).
      # - `active` — non-terminal, non-archived tasks from the live roster,
      #   read through `Owl::Tasks::Api.list` (the index) with each brief
      #   resolved through `Owl::Artifacts::Api.resolve` and read through
      #   `Owl::Storage::Api.read` (the artifact + storage roles).
      # - `all` — active documents followed by archived ones.
      #
      # No direct `File`/`Dir` I/O lives here — every read funnels through a
      # domain facade so the Backend/Internal/Api layering and
      # source-of-truth invariants hold (docs/agents/27). Scope validation is
      # owned by `Owl::Recall::Api`; an unrecognised scope yields `[]` here.
      module CorpusBuilder
        # Heading names (case-folded) whose section bodies feed the corpus.
        # Matched at any heading level so both legacy `# Problem` and newer
        # `## Problem` briefs are picked up.
        TARGET_SECTIONS = %w[problem goal].freeze

        HEADING_PATTERN = /\A#+\s+(.+?)\s*\z/

        # Index statuses that mean a task is finished or closed, so it is not
        # part of the "active" corpus. Mirrors the availability scanner set.
        TERMINAL_STATUSES = %w[archived abandoned done].freeze

        module_function

        def build(root:, scope: 'archive')
          case scope.to_s
          when 'archive' then archived_documents(root: root)
          when 'active' then active_documents(root: root)
          when 'all' then active_documents(root: root) + archived_documents(root: root)
          else []
          end
        end

        def archived_documents(root:)
          listing = Owl::Archive::Api.list(root: root)
          return [] if listing.err?

          listing.value[:archived].map do |entry|
            document(
              task_id: entry[:task_id],
              title: entry[:title].to_s,
              brief_text: archived_brief(root: root, task_id: entry[:task_id]),
              scope: 'archived'
            )
          end
        end

        def active_documents(root:)
          listing = Owl::Tasks::Api.list(root: root)
          return [] if listing.err?

          active_entries(listing.value[:tasks]).map do |entry|
            task_id = entry['task_id'].to_s
            document(
              task_id: task_id,
              title: entry['title'].to_s,
              brief_text: active_brief(root: root, task_id: task_id),
              scope: 'active'
            )
          end
        end

        def active_entries(tasks)
          Array(tasks).select do |entry|
            entry.is_a?(Hash) && !TERMINAL_STATUSES.include?((entry['status'] || 'open').to_s)
          end
        end

        def document(task_id:, title:, brief_text:, scope:)
          text = brief_text.empty? ? title : "#{title} #{brief_text}"
          { task_id: task_id, title: title, text: text, scope: scope }
        end

        def archived_brief(root:, task_id:)
          result = Owl::Archive::Api.read(root: root, task_id: task_id, artifact_key: 'brief')
          return '' if result.err?

          extract_sections(result.value[:body])
        end

        # Resolve and read an active task's `brief` through the artifact +
        # storage roles, never raw FS. Missing/undeclared/unreadable briefs
        # degrade to an empty string so the caller falls back to the title.
        def active_brief(root:, task_id:)
          descriptor = Owl::Artifacts::Api.resolve(root: root, task_id: task_id, artifact_key: 'brief')
          return '' if descriptor.err? || !descriptor.value[:exists]

          body = Owl::Storage::Api.read(path: descriptor.value[:path])
          return '' if body.err?

          extract_sections(body.value)
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
