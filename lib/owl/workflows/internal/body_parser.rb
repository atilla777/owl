# frozen_string_literal: true

require 'yaml'

require_relative '../../result'

module Owl
  module Workflows
    module Internal
      # YAML-parse helpers for workflow source bodies, shared by the scaffolder
      # and the validation loader. `safe_parse` enforces a top-level mapping and
      # surfaces syntax errors as `:workflow_validation_failed`; the duplicate
      # variant-key detection inspects the raw Psych AST (which `YAML.safe_load`
      # silently collapses) so authors get a structured error per offending step.
      module BodyParser
        module_function

        def safe_parse(body_str)
          dup_err = detect_duplicate_variant_keys(body_str.to_s)
          return dup_err if dup_err

          parsed = YAML.safe_load(body_str.to_s, aliases: false)
          unless parsed.is_a?(Hash)
            return Result.err(
              code: :workflow_validation_failed,
              message: 'Workflow body is not a YAML mapping after parse.',
              details: { errors: [{ path: '/', message: 'Top-level YAML must be a mapping.' }] }
            )
          end

          parsed
        rescue Psych::SyntaxError => e
          Result.err(
            code: :workflow_validation_failed,
            message: "Workflow YAML syntax error: #{e.message}",
            details: { errors: [{ path: '/', message: e.message }] }
          )
        end

        def detect_duplicate_variant_keys(body_str)
          doc = Psych.parse(body_str)
          return nil if doc.nil?

          root = doc.root
          return nil unless root.is_a?(Psych::Nodes::Mapping)

          steps_node = mapping_value(root, 'steps')
          return nil unless steps_node.is_a?(Psych::Nodes::Sequence)

          errors = []
          steps_node.children.each_with_index do |step_node, idx|
            next unless step_node.is_a?(Psych::Nodes::Mapping)

            variants_node = mapping_value(step_node, 'variants')
            next unless variants_node.is_a?(Psych::Nodes::Mapping)

            duplicate = find_duplicate_scalar_key(variants_node)
            next if duplicate.nil?

            errors << {
              path: "/steps/#{idx}/variants",
              message: "Duplicate variant key '#{duplicate}' at /steps/#{idx}/variants."
            }
          end

          return nil if errors.empty?

          Result.err(
            code: :workflow_validation_failed,
            message: 'Workflow definition failed validation.',
            details: { errors: errors }
          )
        rescue Psych::SyntaxError
          nil
        end

        def mapping_value(mapping_node, key)
          children = mapping_node.children
          (0...children.length).step(2) do |i|
            k = children[i]
            next unless k.is_a?(Psych::Nodes::Scalar) && k.value == key

            return children[i + 1]
          end
          nil
        end

        def find_duplicate_scalar_key(mapping_node)
          seen = {}
          children = mapping_node.children
          (0...children.length).step(2) do |i|
            k = children[i]
            next unless k.is_a?(Psych::Nodes::Scalar)

            return k.value if seen[k.value]

            seen[k.value] = true
          end
          nil
        end
      end
    end
  end
end
