# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative '../../config/api'
require_relative '../../storage/api'
require_relative '../../tasks/api'
require_relative '../../workflows/api'
require_relative 'artifact_type_loader'
require_relative 'registry_loader'

module Owl
  module Artifacts
    module Internal
      module TaskArtifactResolver
        module_function

        def call(root:, task_id:, artifact_key:)
          task_result = Owl::Tasks::Api.inspect(root: root, task_id: task_id)
          return task_result if task_result.err?

          payload = task_result.value[:payload]
          workflow_key = payload.dig('workflow', 'key')
          unless workflow_key
            return Result.err(
              code: :task_workflow_missing,
              message: "Task '#{task_id}' has no workflow key in task.yaml.",
              details: { task_id: task_id.to_s }
            )
          end

          workflow_artifact = lookup_workflow_artifact(root: root, workflow_key: workflow_key, key: artifact_key)
          return workflow_artifact if workflow_artifact.is_a?(Owl::Result::Err)

          descriptor(
            root: root,
            task_payload: payload,
            workflow_key: workflow_key,
            artifact_key: artifact_key,
            workflow_artifact: workflow_artifact
          )
        end

        def lookup_workflow_artifact(root:, workflow_key:, key:)
          lookup = Owl::Workflows::Api.find(root: root, key: workflow_key)
          return lookup if lookup.err?

          source = lookup.value[:source]
          unless source[:present]
            return Result.err(
              code: :workflow_source_missing,
              message: "Workflow source for '#{workflow_key}' is not present.",
              details: { key: workflow_key.to_s, source_path: source[:source_path] }
            )
          end

          artifacts = source[:body].is_a?(Hash) ? (source[:body]['artifacts'] || {}) : {}
          unless artifacts.is_a?(Hash) && artifacts.key?(key.to_s)
            return Result.err(
              code: :unknown_workflow_artifact,
              message: "Workflow '#{workflow_key}' does not declare artifact '#{key}'.",
              details: { workflow_key: workflow_key.to_s, key: key.to_s, available: available_keys(artifacts) }
            )
          end

          artifacts.fetch(key.to_s)
        end

        def available_keys(artifacts)
          return [] unless artifacts.is_a?(Hash)

          artifacts.keys.map(&:to_s)
        end

        def descriptor(root:, task_payload:, workflow_key:, artifact_key:, workflow_artifact:)
          type_key = workflow_artifact['type'] || workflow_artifact[:type]
          unless type_key
            return Result.err(
              code: :workflow_artifact_type_missing,
              message: "Workflow artifact '#{artifact_key}' is missing a 'type'.",
              details: { workflow_key: workflow_key.to_s, key: artifact_key.to_s }
            )
          end

          path_result = resolve_path(
            root: root, task_payload: task_payload, workflow_artifact: workflow_artifact, artifact_key: artifact_key
          )
          return path_result if path_result.is_a?(Owl::Result::Err)

          type_info = load_type(root: root, type_key: type_key)
          return type_info if type_info.is_a?(Owl::Result::Err)

          Result.ok(build_descriptor(
                      task_payload: task_payload,
                      workflow_key: workflow_key,
                      artifact_key: artifact_key,
                      workflow_artifact: workflow_artifact,
                      type_key: type_key,
                      path_info: path_result,
                      type_info: type_info
                    ))
        end

        def resolve_path(root:, task_payload:, workflow_artifact:, artifact_key:)
          storage = workflow_artifact['storage'] || workflow_artifact[:storage] || {}
          role = storage['role'] || storage[:role]
          template = storage['path'] || storage[:path] || ''
          unless role
            return Result.err(
              code: :workflow_artifact_storage_missing,
              message: "Workflow artifact '#{artifact_key}' has no storage.role.",
              details: { key: artifact_key.to_s }
            )
          end

          profile = load_profile(root: root)
          return profile if profile.is_a?(Owl::Result::Err)

          base = Owl::Storage::Api.resolve(role: role, profile: profile, root: root)
          return base if base.err?

          rel = render_relative(template, task_payload)
          absolute = (Pathname.new(base.value.to_s) + rel).expand_path

          { role: role.to_s, template: template.to_s, absolute: absolute }
        end

        def render_relative(template, task_payload)
          vars = { 'task' => { 'id' => task_payload['id'].to_s, 'slug' => task_payload['slug'].to_s } }
          Owl::Storage::Internal::PathTemplate.render(template.to_s, vars)
        end

        def load_profile(root:)
          config_result = Owl::Config::Api.load(root: root)
          return config_result if config_result.err?

          config_result.value.active_profile
        end

        def load_type(root:, type_key:)
          registry_result = Owl::Artifacts::Api.registry(root: root)
          return registry_result if registry_result.err?

          entry = registry_result.value[:entries].find { |e| e[:key] == type_key.to_s }
          unless entry
            return Result.err(
              code: :unknown_artifact_type,
              message: "Artifact type '#{type_key}' is not declared in .owl/artifacts.yaml.",
              details: { type: type_key.to_s }
            )
          end

          ArtifactTypeLoader.load(root: root, type_key: type_key, registry_entry: entry)
        end

        def build_descriptor(task_payload:, workflow_key:, artifact_key:, workflow_artifact:,
                             type_key:, path_info:, type_info:)
          absolute = path_info[:absolute]
          multiple = boolean_flag?(workflow_artifact, 'multiple')
          optional = boolean_flag?(workflow_artifact, 'optional')

          {
            key: artifact_key.to_s,
            type: type_key.to_s,
            task_id: task_payload['id'].to_s,
            workflow_key: workflow_key.to_s,
            storage_role: path_info[:role],
            storage_path_template: path_info[:template],
            path: absolute.to_s,
            uri: "file://#{absolute}",
            exists: absolute.exist?,
            multiple: multiple,
            optional: optional,
            template_uri: type_info.value[:template_path] ? "file://#{type_info.value[:template_path]}" : nil,
            template_path: type_info.value[:template_path],
            template_present: type_info.value[:template_present],
            validation: type_info.value[:validation],
            front_matter: type_info.value[:front_matter],
            agent_hints: type_info.value[:agent_hints],
            title: workflow_artifact['title'] || workflow_artifact[:title] || type_info.value[:title]
          }
        end

        def boolean_flag?(hash, key)
          return false unless hash.is_a?(Hash)

          value = hash[key] || hash[key.to_sym]
          value == true
        end
      end
    end
  end
end
