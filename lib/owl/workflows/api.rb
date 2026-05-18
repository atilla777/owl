# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../result'
require_relative '../tasks/internal/paths'
require_relative '../tasks/internal/task_reader'
require_relative 'backend'
require_relative 'backends/filesystem'
require_relative 'internal/default_template'
require_relative 'internal/graph_builder'
require_relative 'internal/ready_resolver'
require_relative 'internal/registry_loader'
require_relative 'internal/source_loader'
require_relative 'internal/step_context_resolver'
require_relative 'internal/step_lookup'

module Owl
  module Workflows
    module Api
      module_function

      def registry(root:)
        outcome = Internal::RegistryLoader.load(root: root)
        return Result.err(code: outcome[1], message: outcome[2], details: outcome[3] || {}) if outcome[0] == :err

        Result.ok(outcome[1])
      end

      def list(root:)
        registry_result = registry(root: root)
        return registry_result if registry_result.err?

        registry_data = registry_result.value
        workflows = registry_data[:entries].map do |entry|
          source_info = Internal::SourceLoader.load(root: root, source: entry[:source])

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

      def find(root:, key:)
        registry_result = registry(root: root)
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

        source_info = Internal::SourceLoader.load(root: root, source: entry[:source])
        Result.ok(entry: entry, source: source_info)
      end

      def default_template
        Internal::DefaultTemplate.render
      end

      def seeded_sources
        Internal::DefaultTemplate.source_files
      end

      def graph(root:, workflow_key:)
        lookup = find(root: root, key: workflow_key)
        return lookup if lookup.err?

        source = lookup.value[:source]
        unless source[:present]
          return Result.err(
            code: :workflow_source_missing,
            message: "Workflow source for '#{workflow_key}' is not present.",
            details: { key: workflow_key.to_s, source_path: source[:source_path] }
          )
        end

        body = source[:body]
        steps = body.is_a?(Hash) ? (body['steps'] || body[:steps] || []) : []
        Internal::GraphBuilder.build(steps)
      end

      def definition(root:, workflow_key:, backend: nil)
        lookup = find(root: root, key: workflow_key)
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
          root: root,
          backend: backend
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

      def workflow_source_missing_error(workflow_key, source)
        Result.err(
          code: :workflow_source_missing,
          message: "Workflow source for '#{workflow_key}' is not present.",
          details: { key: workflow_key.to_s, source_path: source[:source_path] }
        )
      end

      def build_steps_lookup(steps:, source_path:, root:, backend:)
        backend ||= resolve_backend(root: root)
        source_dir = Pathname.new(source_path.to_s).dirname

        context_result = Internal::StepContextResolver.call(
          steps: steps,
          backend: backend,
          source_dir: source_dir
        )
        return context_result if context_result.err?

        lookup = Internal::StepLookup.build(steps)
        context_result.value.each do |step_id, ctx|
          lookup[step_id]['context'] = ctx if lookup.key?(step_id)
        end

        Result.ok(lookup)
      end

      def ready_steps(root:, task_id:)
        paths = Owl::Tasks::Internal::Paths.resolve(root: root)
        return paths if paths.err?

        task_read = Owl::Tasks::Internal::TaskReader.read(
          tasks_root: paths.value[:tasks],
          task_id: task_id
        )
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

        graph_result = graph(root: root, workflow_key: workflow_key)
        return graph_result if graph_result.err?

        ready = Internal::ReadyResolver.resolve(
          graph: graph_result.value,
          task_steps: payload['steps'] || []
        )

        Result.ok(
          task_id: task_id.to_s,
          workflow_key: workflow_key,
          ready: ready
        )
      end

      def resolve_backend(root:)
        backend_name = read_backend_name(root: root)
        case backend_name
        when nil, 'filesystem'
          Backends::Filesystem.new(root: root)
        else
          raise UnknownBackendError, "Unknown Owl workflows backend: #{backend_name.inspect}"
        end
      end

      def read_backend_name(root:)
        config_path = Pathname.new(root.to_s) + '.owl/config.yaml'
        return nil unless config_path.exist?

        raw = YAML.safe_load(config_path.read, aliases: false)
        return nil unless raw.is_a?(Hash)

        settings = raw['settings']
        return nil unless settings.is_a?(Hash)

        storage = settings['storage']
        return nil unless storage.is_a?(Hash)

        backend = storage['backend']
        backend.is_a?(String) && !backend.empty? ? backend : nil
      rescue Psych::SyntaxError
        nil
      end

      private_class_method :workflow_source_missing_error, :build_steps_lookup, :read_backend_name
    end
  end
end
