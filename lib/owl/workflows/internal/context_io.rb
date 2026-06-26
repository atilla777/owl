# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative '../../storage/api'
require_relative 'context_reader'
require_relative 'errors'
require_relative 'paths'
require_relative 'registry_writer'

module Owl
  module Workflows
    module Internal
      # Read/write a step's context-file body addressed by `workflow_key` +
      # `step_id` (+ optional variant). `show` resolves and reads the file;
      # `set` guards against managed (Owl-shipped) workflows, re-checks the
      # path-escape boundary, and writes through the Storage role.
      module ContextIo
        module_function

        def show(backend:, workflow_key:, step_id:, variant: nil)
          resolved = resolve_context_target(
            backend: backend, workflow_key: workflow_key, step_id: step_id, variant: variant
          )
          return resolved if resolved.is_a?(Owl::Result::Err)

          read = ContextReader.read(
            source_dir: resolved[:source_dir], step_id: step_id, relative_path: resolved[:relative_path]
          )
          return read if read.err?

          Result.ok(workflow_key: workflow_key.to_s, step_id: step_id.to_s,
                    path: (resolved[:source_dir] + resolved[:relative_path]).to_s, body: read.value)
        end

        def set(backend:, workflow_key:, step_id:, body:, variant: nil)
          guard = RegistryWriter.guard_project_owned(backend: backend, id: workflow_key)
          return guard if guard.is_a?(Owl::Result::Err)

          resolved = resolve_context_target(
            backend: backend, workflow_key: workflow_key, step_id: step_id, variant: variant
          )
          return resolved if resolved.is_a?(Owl::Result::Err)

          target = resolved[:source_dir] + resolved[:relative_path]
          unless Paths.within?(base_dir: resolved[:source_dir], resolved: target.expand_path)
            return Result.err(
              code: :step_context_path_escape,
              message: "Step '#{step_id}' context_file '#{resolved[:relative_path]}' escapes the workflow directory.",
              details: { step_id: step_id.to_s, relative_path: resolved[:relative_path] }
            )
          end

          Owl::Storage::Api.write(path: target, contents: body.to_s)
          Result.ok(workflow_key: workflow_key.to_s, step_id: step_id.to_s, path: target.to_s)
        end

        # Resolve the step's context-file path (variant-aware) relative to the
        # workflow source dir. Returns { source_dir:, relative_path: } or an Err.
        def resolve_context_target(backend:, workflow_key:, step_id:, variant:)
          lookup = backend.find(key: workflow_key)
          return lookup if lookup.err?

          source = lookup.value[:source]
          return Errors.workflow_source_missing(workflow_key, source) unless source[:present]

          source_dir = Pathname.new(source[:source_path].to_s).dirname
          body = source[:body].is_a?(Hash) ? source[:body] : {}
          step = Array(body['steps'] || body[:steps]).find { |s| s.is_a?(Hash) && s['id'].to_s == step_id.to_s }
          return Errors.step_not_found(workflow_key, step_id) unless step

          relative = context_file_for(step: step, variant: variant)
          return relative if relative.is_a?(Owl::Result::Err)

          { source_dir: source_dir, relative_path: relative }
        end

        def context_file_for(step:, variant:)
          if step['variants'].is_a?(Hash)
            name = (variant || step['default_variant']).to_s
            return Errors.missing_context_file(step['id'], 'no variant chosen / default_variant') if name.empty?

            vbody = step['variants'][name]
            return Errors.unknown_variant(step['id'], name, step['variants'].keys) unless vbody.is_a?(Hash)

            file = vbody['context_file'].to_s
            return Errors.missing_context_file(step['id'], "variant '#{name}'") if file.empty?

            return file
          end

          file = step['context_file'].to_s
          return Errors.missing_context_file(step['id'], 'step') if file.empty?

          file
        end
      end
    end
  end
end
