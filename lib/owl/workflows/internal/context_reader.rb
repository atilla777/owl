# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative '../../storage/api'
require_relative 'frontmatter_parser'
require_relative 'paths'

module Owl
  module Workflows
    module Internal
      # Reads a step's context file from the workflow source directory, enforcing
      # the KOS-155 directory-containment guard (no `..` escape) and mapping the
      # Storage `:file_not_found` into the step-scoped
      # `:step_context_file_not_found`. Backs the backend's public
      # `read_step_context` / `read_step_context_frontmatter` surface.
      module ContextReader
        module_function

        def read(source_dir:, step_id:, relative_path:)
          base_dir = Pathname.new(source_dir.to_s).expand_path
          resolved = (base_dir + relative_path.to_s).expand_path

          unless Paths.within?(base_dir: base_dir, resolved: resolved)
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

        def read_frontmatter(source_dir:, step_id:, relative_path:)
          read_result = read(
            source_dir: source_dir, step_id: step_id, relative_path: relative_path
          )
          return read_result if read_result.err?

          FrontmatterParser.parse(read_result.value)
        end
      end
    end
  end
end
