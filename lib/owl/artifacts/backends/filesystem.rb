# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../../result'
require_relative '../../storage/api'
require_relative '../backend'
require_relative '../local'
require_relative '../internal/artifact_type_loader'
require_relative '../internal/artifact_type_validator'
require_relative '../internal/default_template'
require_relative '../internal/registry_loader'
require_relative '../internal/source_loader'
require_relative '../internal/task_artifact_resolver'

module Owl
  module Artifacts
    module Backends
      class Filesystem # rubocop:disable Metrics/ClassLength
        include Owl::Artifacts::Backend

        ID_PATTERN = /\A[a-z][a-z0-9_]*\z/

        # Semantic rules dropped when validating a template body — templates
        # legitimately carry placeholders (TODO, <...>) and empty stub sections.
        TEMPLATE_LENIENT_RULES = %w[forbid_placeholders forbid_empty_sections].freeze

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

          loader_result = Internal::ArtifactTypeLoader.load(root: @root, type_key: key, registry_entry: entry)
          return loader_result if loader_result.err?

          Result.ok(loader_result.value.merge(
                      local: Owl::Artifacts::Local::ArtifactType.new(
                        source_path: loader_result.value[:source_path],
                        template_path: loader_result.value[:template_path]
                      )
                    ))
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

        def scaffold(id:, body: nil, from: nil, force: false)
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

          body_str = resolve_scaffold_body(id: id_str, body: body, from: from)
          return body_str if body_str.is_a?(Owl::Result::Err)

          parsed = safe_parse(body_str)
          return parsed if parsed.is_a?(Owl::Result::Err)

          validation = Internal::ArtifactTypeValidator.validate(body: parsed, source_path: path)
          return validation if validation.err?

          Owl::Storage::Api.write(path: path, contents: body_str)

          template_path = path.dirname + 'templates' + 'default.md'
          unless template_path.exist?
            template_body = clone_template_body(from: from) || Internal::DefaultTemplate.minimal_artifact_template
            Owl::Storage::Api.write(path: template_path, contents: template_body)
          end

          Result.ok(
            id: id_str,
            path: path.to_s,
            template_path: template_path.to_s,
            local: Owl::Artifacts::Local::ArtifactType.new(
              source_path: path.to_s,
              template_path: template_path.to_s
            )
          )
        end

        def template_show(id:, template: 'default')
          template_path = template_source_path(id: id, template: template)
          read_result = Owl::Storage::Api.read(path: template_path)
          if read_result.err?
            return Result.err(
              code: :artifact_template_missing,
              message: "Template '#{template}' for artifact type '#{id}' not found at #{template_path}.",
              details: { id: id.to_s, template: template.to_s, path: template_path.to_s }
            )
          end

          Result.ok(id: id.to_s, template: template.to_s, path: template_path.to_s, body: read_result.value)
        end

        def template_set(id:, body:, template: 'default')
          guard = guard_project_owned(id: id)
          return guard if guard.is_a?(Owl::Result::Err)

          template_path = template_source_path(id: id, template: template)
          Owl::Storage::Api.write(path: template_path, contents: body.to_s)
          Result.ok(id: id.to_s, template: template.to_s, path: template_path.to_s)
        end

        def template_validate(id:, template: 'default')
          require_relative '../../validation/internal/artifact_runner'
          show = template_show(id: id, template: template)
          return show if show.err?

          descriptor = template_descriptor(id: id)
          return descriptor if descriptor.is_a?(Owl::Result::Err)

          violations = Owl::Validation::Internal::ArtifactRunner.validate_body(show.value[:body], descriptor)
          Result.ok(
            id: id.to_s,
            template: template.to_s,
            path: show.value[:path],
            valid: violations.none? { |v| (v[:level] || v['level']).to_s == 'error' },
            violations: violations
          )
        end

        def register(id:, source: nil, managed: false, force: false)
          id_str = id.to_s
          raw, registry_path = load_registry_raw
          return raw if raw.is_a?(Owl::Result::Err)

          entries = raw['artifacts'] ||= {}
          if entries.key?(id_str) && !force
            return Result.err(
              code: :artifact_type_already_registered,
              message: "Artifact type '#{id_str}' is already registered in #{registry_path}.",
              details: { id: id_str, path: registry_path.to_s }
            )
          end

          entries[id_str] = {
            'source' => (source || "artifacts/#{id_str}/artifact.yaml").to_s,
            'managed' => managed ? true : false
          }
          Owl::Storage::Api.write(path: registry_path, contents: YAML.dump(raw))
          Result.ok(id: id_str, source: entries[id_str]['source'], managed: managed ? true : false,
                    path: registry_path.to_s)
        end

        def unregister(id:)
          id_str = id.to_s
          raw, registry_path = load_registry_raw
          return raw if raw.is_a?(Owl::Result::Err)

          entries = raw['artifacts'] || {}
          unless entries.key?(id_str)
            return Result.err(
              code: :artifact_type_not_registered,
              message: "Artifact type '#{id_str}' is not registered in #{registry_path}.",
              details: { id: id_str, path: registry_path.to_s }
            )
          end

          entries.delete(id_str)
          raw['artifacts'] = entries
          Owl::Storage::Api.write(path: registry_path, contents: YAML.dump(raw))
          Result.ok(id: id_str, path: registry_path.to_s)
        end

        def validate(id_or_path:)
          target = id_or_path.to_s
          body, source_path = load_for_validate(target: target)
          return body if body.is_a?(Owl::Result::Err)

          result = Internal::ArtifactTypeValidator.validate(body: body, source_path: source_path)
          return result if result.err?

          Result.ok(
            valid: true,
            id: body['id'],
            source_path: source_path.to_s,
            errors: [],
            local: Owl::Artifacts::Local::ArtifactType.new(
              source_path: source_path.to_s,
              template_path: nil
            )
          )
        end

        def local_paths_for(key: nil)
          if key.nil?
            return Result.err(
              code: :no_local_view,
              message: 'Artifacts local view requires an artifact-type key.',
              details: { backend: self.class.name }
            )
          end

          lookup = find(key: key)
          if lookup.ok?
            return Result.ok(Owl::Artifacts::Local::ArtifactType.new(
                               source_path: lookup.value[:source_path],
                               template_path: lookup.value[:template_path]
                             ))
          end

          # Fall back to convention paths for unregistered keys.
          source_path = artifact_source_path(id: key).to_s
          template_path = (Pathname.new(source_path).dirname + 'templates' + 'default.md').to_s
          Result.ok(Owl::Artifacts::Local::ArtifactType.new(
                      source_path: source_path,
                      template_path: template_path
                    ))
        end

        private

        def artifact_source_path(id:)
          Pathname.new(@root.to_s) + '.owl' + 'artifacts' + id.to_s + 'artifact.yaml'
        end

        def template_source_path(id:, template:)
          name = template.to_s.empty? ? 'default' : template.to_s
          artifact_source_path(id: id).dirname + 'templates' + "#{name}.md"
        end

        def resolve_scaffold_body(id:, body:, from:)
          return body if body.is_a?(String) && !body.empty?

          if from
            clone = find(key: from)
            return clone if clone.err?

            cloned = clone.value[:body].merge('id' => id.to_s)
            return YAML.dump(cloned)
          end

          Internal::DefaultTemplate.minimal_artifact_seed(id: id)
        end

        def clone_template_body(from:)
          return nil unless from

          show = template_show(id: from, template: 'default')
          show.ok? ? show.value[:body] : nil
        end

        def template_descriptor(id:)
          lookup = find(key: id)
          if lookup.ok?
            return { validation: template_mode_rules(lookup.value[:validation]),
                     front_matter: lookup.value[:front_matter] }
          end

          # Unregistered (project-owned, not yet registered) type: read its source directly.
          parsed = safe_parse(artifact_source_path(id: id).read)
          return parsed if parsed.is_a?(Owl::Result::Err)

          { validation: template_mode_rules(parsed['validation'] || {}),
            front_matter: parsed['front_matter'] || {} }
        rescue Errno::ENOENT
          Result.err(
            code: :unknown_artifact_type,
            message: "Artifact type '#{id}' has no source to validate its template against.",
            details: { id: id.to_s }
          )
        end

        # Only structural rules (sections, front matter) apply to a template
        # body; see TEMPLATE_LENIENT_RULES for what is dropped.
        def template_mode_rules(rules)
          (rules || {}).reject { |k, _| TEMPLATE_LENIENT_RULES.include?(k.to_s) }
        end

        def guard_project_owned(id:)
          registry_result = registry
          return registry_result if registry_result.err?

          entry = registry_result.value[:entries].find { |e| e[:key] == id.to_s }
          return nil unless entry && entry[:managed]

          Result.err(
            code: :artifact_type_managed,
            message: "Artifact type '#{id}' is managed (Owl-shipped) and read-only. " \
                     "Clone it first: owl artifact-type new --from #{id} --id <new> --register.",
            details: { id: id.to_s }
          )
        end

        def load_registry_raw
          registry_path = Pathname.new(@root.to_s) + '.owl' + 'artifacts.yaml'
          unless registry_path.exist?
            return [
              Result.err(
                code: :artifacts_registry_missing,
                message: "Artifacts registry not found at #{registry_path}.",
                details: { path: registry_path.to_s }
              ),
              registry_path
            ]
          end

          raw = YAML.safe_load(registry_path.read, aliases: false)
          raw = {} unless raw.is_a?(Hash)
          [raw, registry_path]
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
