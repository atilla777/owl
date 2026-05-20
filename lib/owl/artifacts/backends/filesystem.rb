# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../../result'
require_relative '../../storage/api'
require_relative '../backend'
require_relative '../internal/artifact_type_loader'
require_relative '../internal/artifact_type_validator'
require_relative '../internal/default_template'
require_relative '../internal/registry_loader'
require_relative '../internal/source_loader'
require_relative '../internal/task_artifact_resolver'

module Owl
  module Artifacts
    module Backends
      class Filesystem
        include Owl::Artifacts::Backend

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
          artifacts = registry_data[:entries].map do |entry|
            source_info = Internal::SourceLoader.load(root: @root, source: entry[:source])

            {
              key: entry[:key],
              title: source_info[:title],
              kind: source_info[:kind],
              description: source_info[:description],
              source: entry[:source],
              source_present: source_info[:present]
            }
          end

          Result.ok(artifacts)
        end

        def find(key:)
          registry_result = registry
          return registry_result if registry_result.err?

          entry = registry_result.value[:entries].find { |e| e[:key] == key.to_s }
          unless entry
            return Result.err(
              code: :unknown_artifact_type,
              message: "Artifact type '#{key}' is not declared in .owl/artifacts.yaml.",
              details: { key: key.to_s, available: registry_result.value[:entries].map { |e| e[:key] } }
            )
          end

          Internal::ArtifactTypeLoader.load(root: @root, type_key: key, registry_entry: entry)
        end

        def resolve(task_id:, artifact_key:)
          Internal::TaskArtifactResolver.call(root: @root, task_id: task_id, artifact_key: artifact_key)
        end

        def default_template
          Internal::DefaultTemplate.render
        end

        def seeded_sources
          Internal::DefaultTemplate.source_files
        end

        def scaffold(id:, body: nil, force: false)
          id_str = id.to_s
          unless id_str.match?(ID_PATTERN)
            return Result.err(
              code: :invalid_artifact_type_id,
              message: "Artifact type id '#{id_str}' must match /^[a-z][a-z0-9_]*$/.",
              details: { id: id_str }
            )
          end

          path = artifact_source_path(id: id_str)
          if path.exist? && !force
            return Result.err(
              code: :artifact_type_already_exists,
              message: "Artifact type source already exists at #{path}.",
              details: { id: id_str, path: path.to_s }
            )
          end

          body_str = if body.is_a?(String) && !body.empty?
                       body
                     else
                       Internal::DefaultTemplate.minimal_artifact_seed(id: id_str)
                     end

          parsed = safe_parse(body_str)
          return parsed if parsed.is_a?(Owl::Result::Err)

          validation = Internal::ArtifactTypeValidator.validate(body: parsed, source_path: path)
          return validation if validation.err?

          Owl::Storage::Api.write(path: path, contents: body_str)

          template_path = path.dirname + 'templates' + 'default.md'
          unless template_path.exist?
            Owl::Storage::Api.write(path: template_path, contents: Internal::DefaultTemplate.minimal_artifact_template)
          end

          Result.ok(id: id_str, path: path.to_s, template_path: template_path.to_s)
        end

        def validate(id_or_path:)
          target = id_or_path.to_s
          body, source_path = load_for_validate(target: target)
          return body if body.is_a?(Owl::Result::Err)

          result = Internal::ArtifactTypeValidator.validate(body: body, source_path: source_path)
          return result if result.err?

          Result.ok(valid: true, id: body['id'], source_path: source_path.to_s, errors: [])
        end

        private

        def artifact_source_path(id:)
          Pathname.new(@root.to_s) + '.owl' + 'artifacts' + id.to_s + 'artifact.yaml'
        end

        def safe_parse(body_str)
          parsed = YAML.safe_load(body_str.to_s, aliases: false)
          unless parsed.is_a?(Hash)
            return Result.err(
              code: :artifact_type_validation_failed,
              message: 'Artifact type body is not a YAML mapping after parse.',
              details: { errors: [{ path: '/', message: 'Top-level YAML must be a mapping.' }] }
            )
          end

          parsed
        rescue Psych::SyntaxError => e
          Result.err(
            code: :artifact_type_validation_failed,
            message: "Artifact type YAML syntax error: #{e.message}",
            details: { errors: [{ path: '/', message: e.message }] }
          )
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
                code: :artifact_type_source_missing,
                message: "Artifact type source file not found at #{path}.",
                details: { path: path.to_s }
              ),
              path
            ]
          end

          parsed = safe_parse(path.read)
          [parsed, path]
        end

        def load_from_registry(key:)
          lookup = find(key: key)
          return [lookup, nil] if lookup.err?

          source_path = lookup.value[:source_path] ? Pathname.new(lookup.value[:source_path]) : nil
          body = lookup.value[:body] || {}
          [body, source_path]
        end
      end
    end
  end
end
