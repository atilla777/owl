# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative '../local'
require_relative 'body_parser'
require_relative 'workflow_validator'

module Owl
  module Workflows
    module Internal
      # Drives `owl workflow validate`: loads a workflow body from either a path
      # (`*.yaml` / contains `/`) or the registry by key, then runs schema
      # validation followed by the filesystem-ref check (which needs `backend`
      # to read per-step context files).
      module ValidationLoader
        module_function

        def call(root:, backend:, id_or_path:)
          target = id_or_path.to_s
          body, source_path = load_for_validate(backend: backend, target: target)
          return body if body.is_a?(Owl::Result::Err)

          result = WorkflowValidator.validate(root: root, body: body, source_path: source_path)
          return result if result.err?

          source_dir = source_path&.dirname
          fs_result = WorkflowValidator.validate_filesystem_refs(
            body: body, backend: backend, source_dir: source_dir
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

        def load_for_validate(backend:, target:)
          if target.include?('/') || target.end_with?('.yaml') || target.end_with?('.yml')
            load_from_path(target)
          else
            load_from_registry(backend: backend, key: target)
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

          parsed = BodyParser.safe_parse(path.read)
          return [parsed, path] if parsed.is_a?(Owl::Result::Err)

          [parsed, path]
        end

        def load_from_registry(backend:, key:)
          lookup = backend.find(key: key)
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
            dup_err = BodyParser.detect_duplicate_variant_keys(path.read)
            return [dup_err, path] if dup_err
          end

          [source[:body], path]
        end
      end
    end
  end
end
