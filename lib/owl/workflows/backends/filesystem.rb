# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative '../../storage/api'
require_relative '../backend'

module Owl
  module Workflows
    module Backends
      class Filesystem
        include Owl::Workflows::Backend

        def initialize(root:)
          @root = root
        end

        def read_step_context(source_dir:, step_id:, relative_path:)
          base_dir = Pathname.new(source_dir.to_s).expand_path
          resolved = (base_dir + relative_path.to_s).expand_path

          unless within?(base_dir: base_dir, resolved: resolved)
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

        private

        def within?(base_dir:, resolved:)
          base_str = base_dir.to_s
          resolved_str = resolved.to_s
          return true if resolved_str == base_str

          resolved_str.start_with?("#{base_str}#{File::SEPARATOR}")
        end
      end
    end
  end
end
