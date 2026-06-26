# frozen_string_literal: true

require 'yaml'

require_relative '../../result'
require_relative '../../storage/api'
require_relative 'paths'

module Owl
  module Workflows
    module Internal
      # Mutates the `.owl/workflows.yaml` registry: register/unregister a
      # workflow entry and guard project-owned (non-managed) edits. Reads the
      # raw registry mapping, applies the change, and rewrites it through the
      # Storage role.
      module RegistryWriter
        module_function

        def register(root:, id:, enabled: true, managed: false, title: nil, source: nil, force: false)
          id_str = id.to_s
          raw, registry_path = load_registry_raw(root: root)
          return raw if raw.is_a?(Owl::Result::Err)

          entries = raw['workflows'] ||= {}
          if entries.key?(id_str) && !force
            return Result.err(
              code: :workflow_already_registered,
              message: "Workflow '#{id_str}' is already registered in #{registry_path}.",
              details: { id: id_str, path: registry_path.to_s }
            )
          end

          entry = { 'enabled' => enabled ? true : false,
                    'source' => (source || "workflows/#{id_str}/workflow.yaml").to_s,
                    'managed' => managed ? true : false }
          entry['title'] = title.to_s if title
          entries[id_str] = entry
          Owl::Storage::Api.write(path: registry_path, contents: YAML.dump(raw))
          Result.ok(id: id_str, enabled: entry['enabled'], managed: entry['managed'],
                    source: entry['source'], path: registry_path.to_s)
        end

        def unregister(root:, id:)
          id_str = id.to_s
          raw, registry_path = load_registry_raw(root: root)
          return raw if raw.is_a?(Owl::Result::Err)

          entries = raw['workflows'] || {}
          unless entries.key?(id_str)
            return Result.err(
              code: :workflow_not_registered,
              message: "Workflow '#{id_str}' is not registered in #{registry_path}.",
              details: { id: id_str, path: registry_path.to_s }
            )
          end

          entries.delete(id_str)
          raw['workflows'] = entries
          Owl::Storage::Api.write(path: registry_path, contents: YAML.dump(raw))
          Result.ok(id: id_str, path: registry_path.to_s)
        end

        # Returns nil when the workflow is project-owned (writable), or an Err
        # when it is Owl-managed (read-only). `backend` supplies `registry`.
        def guard_project_owned(backend:, id:)
          registry_result = backend.registry
          return registry_result if registry_result.err?

          entry = registry_result.value[:entries].find { |e| e[:key] == id.to_s }
          return nil unless entry && entry[:managed]

          Result.err(
            code: :workflow_managed,
            message: "Workflow '#{id}' is managed (Owl-shipped) and read-only. " \
                     "Clone it first: owl workflow new --from #{id} --id <new> --register.",
            details: { id: id.to_s }
          )
        end

        def load_registry_raw(root:)
          registry_path = Paths.registry_path(root: root)
          unless registry_path.exist?
            return [
              Result.err(
                code: :workflows_registry_missing,
                message: "Workflows registry not found at #{registry_path}.",
                details: { path: registry_path.to_s }
              ),
              registry_path
            ]
          end

          raw = YAML.safe_load(registry_path.read, aliases: false)
          raw = {} unless raw.is_a?(Hash)
          [raw, registry_path]
        end
      end
    end
  end
end
