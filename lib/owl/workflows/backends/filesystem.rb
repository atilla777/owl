# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../../result'
require_relative '../../storage/api'
require_relative '../backend'
require_relative '../local'
require_relative '../internal/default_template'
require_relative '../internal/frontmatter_parser'
require_relative '../internal/graph_builder'
require_relative '../internal/ready_resolver'
require_relative '../internal/registry_loader'
require_relative '../internal/source_loader'
require_relative '../internal/step_context_resolver'
require_relative '../internal/step_lookup'
require_relative '../internal/workflow_validator'

module Owl
  module Workflows
    module Backends
      class Filesystem # rubocop:disable Metrics/ClassLength
        include Owl::Workflows::Backend

        ID_PATTERN = /\A[a-z][a-z0-9_]*\z/

        def initialize(root:)
          @root = root
        end

        def registry
          outcome = Internal::RegistryLoader.load(root: @root)
          return Result.err(code: outcome[1], message: outcome[2], details: outcome[3] || {}) if outcome[0] == :err

          Result.ok(outcome[1])
        end

        def list
          registry_result = registry
          return registry_result if registry_result.err?

          registry_data = registry_result.value
          workflows = registry_data[:entries].map do |entry|
            source_info = Internal::SourceLoader.load(root: @root, source: entry[:source])

            {
              key: entry[:key],
              enabled: entry[:enabled],
              title: entry[:title],
              description: source_info[:description],
              kind: source_info[:kind],
              source: entry[:source],
              source_present: source_info[:present],
              aliases: entry[:aliases],
              priority: entry[:priority],
              version: entry[:version]
            }
          end

          Result.ok(workflows)
        end

        def find(key:)
          registry_result = registry
          return registry_result if registry_result.err?

          entries = registry_result.value[:entries]
          entry = entries.find { |e| e[:key] == key.to_s }

          unless entry
            return Result.err(
              code: :unknown_workflow,
              message: "Workflow '#{key}' is not defined in the registry",
              details: { key: key.to_s, available: entries.map { |e| e[:key] } }
            )
          end

          source_info = Internal::SourceLoader.load(root: @root, source: entry[:source])
          Result.ok(
            entry: entry,
            source: source_info,
            local: Owl::Workflows::Local::WorkflowFile.new(source_path: source_info[:source_path].to_s)
          )
        end

        def default_template
          Internal::DefaultTemplate.render
        end

        def seeded_sources
          Internal::DefaultTemplate.source_files
        end

        def scaffold(id:, body: nil, kind: 'task', from: nil, force: false)
          id_str = id.to_s
          unless id_str.match?(ID_PATTERN)
            return Result.err(
              code: :invalid_workflow_id,
              message: "Workflow id '#{id_str}' must match /^[a-z][a-z0-9_]*$/.",
              details: { id: id_str }
            )
          end

          path = workflow_source_path(id: id_str)
          if path.exist? && !force
            return Result.err(
              code: :workflow_already_exists,
              message: "Workflow source already exists at #{path}.",
              details: { id: id_str, path: path.to_s }
            )
          end

          body_str = resolve_scaffold_body(id: id_str, body: body, kind: kind, from: from)
          return body_str if body_str.is_a?(Owl::Result::Err)

          parsed = safe_parse(body_str)
          return parsed if parsed.is_a?(Owl::Result::Err)

          validation = Internal::WorkflowValidator.validate(root: @root, body: parsed, source_path: path)
          return validation if validation.err?

          Owl::Storage::Api.write(path: path, contents: body_str)

          Result.ok(
            id: id_str,
            path: path.to_s,
            kind: parsed['kind'] || kind.to_s,
            local: Owl::Workflows::Local::WorkflowFile.new(source_path: path.to_s)
          )
        end

        def validate(id_or_path:)
          target = id_or_path.to_s
          body, source_path = load_for_validate(target: target)
          return body if body.is_a?(Owl::Result::Err)

          result = Internal::WorkflowValidator.validate(root: @root, body: body, source_path: source_path)
          return result if result.err?

          source_dir = source_path&.dirname
          fs_result = Internal::WorkflowValidator.validate_filesystem_refs(
            body: body, backend: self, source_dir: source_dir
          )
          return fs_result if fs_result.err?

          Result.ok(
            valid: true,
            id: body['id'],
            source_path: source_path.to_s,
            errors: [],
            local: Owl::Workflows::Local::WorkflowFile.new(source_path: source_path.to_s)
          )
        end

        def graph(workflow_key:)
          lookup = find(key: workflow_key)
          return lookup if lookup.err?

          source = lookup.value[:source]
          return workflow_source_missing_error(workflow_key, source) unless source[:present]

          body = source[:body]
          steps = body.is_a?(Hash) ? (body['steps'] || body[:steps] || []) : []
          Internal::GraphBuilder.build(steps)
        end

        def definition(workflow_key:, backend: nil, step_variants: {})
          lookup = find(key: workflow_key)
          return lookup if lookup.err?

          source = lookup.value[:source]
          return workflow_source_missing_error(workflow_key, source) unless source[:present]

          body = source[:body].is_a?(Hash) ? source[:body] : {}
          steps = body['steps'] || body[:steps] || []

          graph_result = Internal::GraphBuilder.build(steps)
          return graph_result if graph_result.err?

          steps_lookup_result = build_steps_lookup(
            steps: steps,
            source_path: source[:source_path],
            backend: backend,
            step_variants: step_variants
          )
          return steps_lookup_result if steps_lookup_result.err?

          Result.ok(
            key: workflow_key.to_s,
            body: body,
            steps: steps_lookup_result.value,
            graph: graph_result.value,
            artifacts: body['artifacts'].is_a?(Hash) ? body['artifacts'] : {}
          )
        end

        def ready_steps(task_id:)
          require_relative '../../tasks/api'
          task_read = Owl::Tasks::Api.inspect(root: @root, task_id: task_id)
          return task_read if task_read.err?

          payload = task_read.value[:payload]
          workflow_key = payload.dig('workflow', 'key')
          unless workflow_key
            return Result.err(
              code: :task_workflow_missing,
              message: "Task '#{task_id}' has no workflow key in task.yaml.",
              details: { task_id: task_id.to_s }
            )
          end

          graph_result = graph(workflow_key: workflow_key)
          return graph_result if graph_result.err?

          definition_steps = definition_steps_for(workflow_key: workflow_key)

          ready = Internal::ReadyResolver.resolve(
            graph: graph_result.value,
            task_steps: payload['steps'] || [],
            definition_steps: definition_steps
          )

          Result.ok(
            task_id: task_id.to_s,
            workflow_key: workflow_key,
            ready: ready
          )
        end

        def definition_steps_for(workflow_key:)
          lookup = find(key: workflow_key)
          return {} if lookup.err?

          source = lookup.value[:source]
          return {} unless source[:present]

          body = source[:body].is_a?(Hash) ? source[:body] : {}
          steps = body['steps'] || body[:steps] || []
          Internal::StepLookup.build(steps)
        end

        def read_step_context(source_dir:, step_id:, relative_path:)
          base_dir = Pathname.new(source_dir.to_s).expand_path
          resolved = (base_dir + relative_path.to_s).expand_path

          unless within?(base_dir: base_dir, resolved: resolved)
            return Result.err(
              code: :step_context_path_escape,
              message: "Step '#{step_id}' context_file '#{relative_path}' escapes the workflow source directory.",
              details: {
                step_id: step_id.to_s,
                relative_path: relative_path.to_s
              }
            )
          end

          read_result = Owl::Storage::Api.read(path: resolved)
          return read_result if read_result.ok?

          if read_result.code == :file_not_found
            return Result.err(
              code: :step_context_file_not_found,
              message: "Step '#{step_id}' context_file '#{relative_path}' not found at #{resolved}.",
              details: {
                step_id: step_id.to_s,
                relative_path: relative_path.to_s,
                resolved_path: resolved.to_s
              }
            )
          end

          read_result
        end

        def read_step_context_frontmatter(source_dir:, step_id:, relative_path:)
          read_result = read_step_context(
            source_dir: source_dir, step_id: step_id, relative_path: relative_path
          )
          return read_result if read_result.err?

          Internal::FrontmatterParser.parse(read_result.value)
        end

        def local_paths_for(key: nil)
          if key.nil?
            return Result.err(
              code: :no_local_view,
              message: 'Workflows local view requires a workflow key.',
              details: { backend: self.class.name }
            )
          end

          lookup = find(key: key)
          source_path = if lookup.ok?
                          lookup.value[:source][:source_path].to_s
                        else
                          workflow_source_path(id: key).to_s
                        end
          Result.ok(Owl::Workflows::Local::WorkflowFile.new(source_path: source_path))
        end

        private

        def within?(base_dir:, resolved:)
          base_str = base_dir.to_s
          resolved_str = resolved.to_s
          return true if resolved_str == base_str

          resolved_str.start_with?("#{base_str}#{File::SEPARATOR}")
        end

        def workflow_source_path(id:)
          Pathname.new(@root.to_s) + '.owl' + 'workflows' + id.to_s + 'workflow.yaml'
        end

        def workflow_source_missing_error(workflow_key, source)
          Result.err(
            code: :workflow_source_missing,
            message: "Workflow source for '#{workflow_key}' is not present.",
            details: { key: workflow_key.to_s, source_path: source[:source_path] }
          )
        end

        def build_steps_lookup(steps:, source_path:, backend:, step_variants:)
          backend ||= self
          source_dir = Pathname.new(source_path.to_s).dirname

          context_result = Internal::StepContextResolver.call(
            steps: steps,
            backend: backend,
            source_dir: source_dir,
            step_variants: step_variants
          )
          return context_result if context_result.err?

          lookup = Internal::StepLookup.build(steps)
          context_result.value.each do |step_id, ctx|
            lookup[step_id]['context'] = ctx if lookup.key?(step_id)
          end

          Result.ok(lookup)
        end

        def resolve_scaffold_body(id:, body:, kind:, from:)
          return body if body.is_a?(String) && !body.empty?

          if from
            clone = find(key: from)
            return clone if clone.err?

            source = clone.value[:source]
            unless source[:present] && source[:body].is_a?(Hash)
              return Result.err(
                code: :workflow_source_missing,
                message: "Cannot clone workflow '#{from}': source is missing or empty.",
                details: { from: from.to_s }
              )
            end

            cloned = source[:body].merge('id' => id.to_s)
            return YAML.dump(cloned)
          end

          Internal::DefaultTemplate.minimal_seed(id: id, kind: kind)
        end

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

        def load_for_validate(target:)
          if target.include?('/') || target.end_with?('.yaml') || target.end_with?('.yml')
            load_from_path(target)
          else
            load_from_registry(key: target)
          end
        end

        def load_from_path(target)
          path = Pathname.new(target).expand_path
          unless path.exist?
            return [
              Result.err(
                code: :workflow_source_missing,
                message: "Workflow source file not found at #{path}.",
                details: { path: path.to_s }
              ),
              path
            ]
          end

          parsed = safe_parse(path.read)
          return [parsed, path] if parsed.is_a?(Owl::Result::Err)

          [parsed, path]
        end

        def load_from_registry(key:)
          lookup = find(key: key)
          return [lookup, nil] if lookup.err?

          source = lookup.value[:source]
          path = source[:source_path] ? Pathname.new(source[:source_path]) : nil
          unless source[:present] && source[:body].is_a?(Hash)
            return [
              Result.err(
                code: :workflow_source_missing,
                message: "Workflow source for '#{key}' is not present.",
                details: { key: key.to_s, source_path: path&.to_s }
              ),
              path
            ]
          end

          if path&.exist?
            dup_err = detect_duplicate_variant_keys(path.read)
            return [dup_err, path] if dup_err
          end

          [source[:body], path]
        end
      end
    end
  end
end
