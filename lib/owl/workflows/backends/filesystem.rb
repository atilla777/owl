# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative '../backend'
require_relative '../local'
require_relative '../internal/context_io'
require_relative '../internal/context_reader'
require_relative '../internal/default_template'
require_relative '../internal/errors'
require_relative '../internal/graph_builder'
require_relative '../internal/paths'
require_relative '../internal/ready_steps_service'
require_relative '../internal/registry_loader'
require_relative '../internal/registry_writer'
require_relative '../internal/scaffolder'
require_relative '../internal/source_loader'
require_relative '../internal/steps_lookup_builder'
require_relative '../internal/validation_loader'

module Owl
  module Workflows
    module Backends
      # Filesystem implementation of the workflows Backend contract. A thin
      # delegator: each public operation reads/writes `.owl/` through a focused
      # `Workflows::Internal::*` service object; this class only wires `@root`
      # and the backend instance (for self-referential `find`/`graph` lookups)
      # into those services.
      class Filesystem
        include Owl::Workflows::Backend

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
          Internal::Scaffolder.call(
            root: @root, backend: self, id: id, body: body, kind: kind, from: from, force: force
          )
        end

        def validate(id_or_path:)
          Internal::ValidationLoader.call(root: @root, backend: self, id_or_path: id_or_path)
        end

        def source_show(id:)
          lookup = find(key: id)
          return lookup if lookup.err?

          source = lookup.value[:source]
          path = source[:source_path] ? Pathname.new(source[:source_path]) : nil
          unless path&.exist?
            return Result.err(
              code: :workflow_source_missing,
              message: "Workflow source for '#{id}' is not present.",
              details: { key: id.to_s, source_path: path&.to_s }
            )
          end

          Result.ok(id: id.to_s, path: path.to_s, body: path.read)
        end

        def register(id:, enabled: true, managed: false, title: nil, source: nil, force: false)
          Internal::RegistryWriter.register(
            root: @root, id: id, enabled: enabled, managed: managed, title: title, source: source, force: force
          )
        end

        def unregister(id:)
          Internal::RegistryWriter.unregister(root: @root, id: id)
        end

        def context_show(workflow_key:, step_id:, variant: nil)
          Internal::ContextIo.show(backend: self, workflow_key: workflow_key, step_id: step_id, variant: variant)
        end

        def context_set(workflow_key:, step_id:, body:, variant: nil)
          Internal::ContextIo.set(
            backend: self, workflow_key: workflow_key, step_id: step_id, body: body, variant: variant
          )
        end

        def graph(workflow_key:)
          lookup = find(key: workflow_key)
          return lookup if lookup.err?

          source = lookup.value[:source]
          return Internal::Errors.workflow_source_missing(workflow_key, source) unless source[:present]

          body = source[:body]
          steps = body.is_a?(Hash) ? (body['steps'] || body[:steps] || []) : []
          Internal::GraphBuilder.build(steps)
        end

        def definition(workflow_key:, backend: nil, step_variants: {})
          lookup = find(key: workflow_key)
          return lookup if lookup.err?

          source = lookup.value[:source]
          return Internal::Errors.workflow_source_missing(workflow_key, source) unless source[:present]

          body = source[:body].is_a?(Hash) ? source[:body] : {}
          steps = body['steps'] || body[:steps] || []

          graph_result = Internal::GraphBuilder.build(steps)
          return graph_result if graph_result.err?

          steps_lookup_result = Internal::StepsLookupBuilder.build(
            steps: steps,
            source_path: source[:source_path],
            backend: backend || self,
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
          Internal::ReadyStepsService.call(root: @root, backend: self, task_id: task_id)
        end

        def read_step_context(source_dir:, step_id:, relative_path:)
          Internal::ContextReader.read(source_dir: source_dir, step_id: step_id, relative_path: relative_path)
        end

        def read_step_context_frontmatter(source_dir:, step_id:, relative_path:)
          Internal::ContextReader.read_frontmatter(
            source_dir: source_dir, step_id: step_id, relative_path: relative_path
          )
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
                          Internal::Paths.workflow_source_path(root: @root, id: key).to_s
                        end
          Result.ok(Owl::Workflows::Local::WorkflowFile.new(source_path: source_path))
        end
      end
    end
  end
end
