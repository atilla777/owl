# frozen_string_literal: true

require 'yaml'

require_relative '../../result'
require_relative '../../storage/api'
require_relative '../local'
require_relative 'body_parser'
require_relative 'default_template'
require_relative 'paths'
require_relative 'workflow_validator'

module Owl
  module Workflows
    module Internal
      # Creates a new workflow source file under `.owl/workflows/<id>/`. Resolves
      # the body (explicit body, `--from` clone, or the default minimal seed),
      # parses + schema-validates it, then writes it through the Storage role.
      # `backend` supplies `find` for the clone path.
      module Scaffolder
        ID_PATTERN = /\A[a-z][a-z0-9_]*\z/

        module_function

        def call(root:, backend:, id:, body: nil, kind: 'task', from: nil, force: false)
          id_str = id.to_s
          unless id_str.match?(ID_PATTERN)
            return Result.err(
              code: :invalid_workflow_id,
              message: "Workflow id '#{id_str}' must match /^[a-z][a-z0-9_]*$/.",
              details: { id: id_str }
            )
          end

          path = Paths.workflow_source_path(root: root, id: id_str)
          if path.exist? && !force
            return Result.err(
              code: :workflow_already_exists,
              message: "Workflow source already exists at #{path}.",
              details: { id: id_str, path: path.to_s }
            )
          end

          body_str = resolve_scaffold_body(backend: backend, id: id_str, body: body, kind: kind, from: from)
          return body_str if body_str.is_a?(Owl::Result::Err)

          parsed = BodyParser.safe_parse(body_str)
          return parsed if parsed.is_a?(Owl::Result::Err)

          validation = WorkflowValidator.validate(root: root, body: parsed, source_path: path)
          return validation if validation.err?

          Owl::Storage::Api.write(path: path, contents: body_str)

          Result.ok(
            id: id_str,
            path: path.to_s,
            kind: parsed['kind'] || kind.to_s,
            local: Owl::Workflows::Local::WorkflowFile.new(source_path: path.to_s)
          )
        end

        def resolve_scaffold_body(backend:, id:, body:, kind:, from:)
          return body if body.is_a?(String) && !body.empty?

          if from
            clone = backend.find(key: from)
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

          DefaultTemplate.minimal_seed(id: id, kind: kind)
        end
      end
    end
  end
end
