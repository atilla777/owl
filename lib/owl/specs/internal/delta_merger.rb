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
      # after `### Requirement:`). Errors:
      #   * `:delta_target_missing` — a REMOVED/MODIFIED name is absent from the
      #     spec.
      #   * `:delta_conflict` — an ADDED name already exists in the spec.
      module DeltaMerger
        module_function

        def apply(spec_model, delta)
          requirements = spec_model[:requirements].map(&:dup)

          removed = remove(requirements, delta[:removed])
          return removed if removed.err?

          modified = modify(removed.value, delta[:modified])
          return modified if modified.err?

          added = add(modified.value, delta[:added])
          return added if added.err?

          Result.ok(spec_model.merge(requirements: added.value))
        end

        # --- internals -----------------------------------------------------

        def remove(requirements, names)
          names.each do |name|
            index = index_of(requirements, name)
            return target_missing(name, 'REMOVED') unless index

            requirements.delete_at(index)
          end
          Result.ok(requirements)
        end

        def modify(requirements, blocks)
          blocks.each do |block|
            index = index_of(requirements, block[:name])
            return target_missing(block[:name], 'MODIFIED') unless index

            requirements[index] = normalize(block)
          end
          Result.ok(requirements)
        end

        def add(requirements, blocks)
          blocks.each do |block|
            return conflict(block[:name]) if index_of(requirements, block[:name])

            requirements << normalize(block)
          end
          Result.ok(requirements)
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
            message: "ADDED requirement '#{name}' already exists in the spec.",
            details: { name: name }
          )
        end

        private_class_method :remove, :modify, :add, :index_of, :normalize,
                             :target_missing, :conflict
      end
    end
  end
end
