# frozen_string_literal: true

require_relative '../../result'

module Owl
  module Specs
    module Internal
      # Applies a parsed delta to a parsed spec model deterministically.
      #
      # `apply(spec_model, delta)` returns `Result.ok(new_model)` or a structured
      # error. Operations run in a fixed canonical order — REMOVED, then
      # MODIFIED, then ADDED — so the same (spec, delta) pair always yields the
      # same requirement list and therefore byte-identical serialization.
      #
      # Requirement names are matched exactly (case-sensitive, trimmed title text
      # after `### Requirement:`). Application is idempotent: re-applying an
      # already-applied delta is a no-op (it never errors), while a genuine
      # conflict still errors. Errors:
      #   * `:delta_target_missing` — a MODIFIED name is absent from the spec.
      #     (A REMOVED name that is absent is treated as already-removed — a
      #     no-op, not an error.)
      #   * `:delta_conflict` — an ADDED name already exists in the spec with
      #     DIFFERENT (normalized) content. An ADDED name already present with
      #     IDENTICAL content is an already-applied no-op, not a conflict.
      #
      # The returned model carries an `:unchanged` summary
      # (`{ added:, modified:, removed: }`) counting the no-op operations so the
      # engine can report them separately from truly-applied changes.
      module DeltaMerger
        module_function

        def apply(spec_model, delta)
          requirements = spec_model[:requirements].map(&:dup)

          removed = remove(requirements, delta[:removed])
          return removed if removed.err?

          modified = modify(removed.value[:requirements], delta[:modified])
          return modified if modified.err?

          added = add(modified.value[:requirements], delta[:added])
          return added if added.err?

          unchanged = { added: added.value[:unchanged], modified: modified.value[:unchanged],
                        removed: removed.value[:unchanged] }
          Result.ok(spec_model.merge(requirements: added.value[:requirements], unchanged: unchanged))
        end

        # --- internals -----------------------------------------------------

        def remove(requirements, names)
          unchanged = 0
          names.each do |name|
            index = index_of(requirements, name)
            if index
              requirements.delete_at(index)
            else
              unchanged += 1 # already removed — idempotent no-op
            end
          end
          Result.ok(requirements: requirements, unchanged: unchanged)
        end

        def modify(requirements, blocks)
          unchanged = 0
          blocks.each do |block|
            index = index_of(requirements, block[:name])
            return target_missing(block[:name], 'MODIFIED') unless index

            normalized = normalize(block)
            unchanged += 1 if requirements[index] == normalized # re-set to same content — no-op
            requirements[index] = normalized
          end
          Result.ok(requirements: requirements, unchanged: unchanged)
        end

        def add(requirements, blocks)
          unchanged = 0
          blocks.each do |block|
            index = index_of(requirements, block[:name])
            normalized = normalize(block)
            if index.nil?
              requirements << normalized
            elsif requirements[index] == normalized
              unchanged += 1 # already applied with identical content — no-op
            else
              return conflict(block[:name]) # same name, different content — genuine conflict
            end
          end
          Result.ok(requirements: requirements, unchanged: unchanged)
        end

        def index_of(requirements, name)
          requirements.index { |req| req[:name] == name }
        end

        # Inserted/replacement blocks are guaranteed to end with a single
        # newline so concatenation in `SpecDocument.serialize` never glues a
        # block to the following block, the tail, or the file end.
        def normalize(block)
          body = block[:body]
          body = "#{body}\n" unless body.end_with?("\n")
          { name: block[:name], heading: block[:heading], body: body }
        end

        def target_missing(name, operation)
          Result.err(
            code: :delta_target_missing,
            message: "#{operation} requirement '#{name}' is not present in the spec.",
            details: { name: name, operation: operation.downcase }
          )
        end

        def conflict(name)
          Result.err(
            code: :delta_conflict,
            message: "ADDED requirement '#{name}' already exists in the spec with different content.",
            details: { name: name }
          )
        end

        private_class_method :remove, :modify, :add, :index_of, :normalize,
                             :target_missing, :conflict
      end
    end
  end
end
