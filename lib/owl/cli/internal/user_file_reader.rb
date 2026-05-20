# frozen_string_literal: true

require_relative '../../result'

module Owl
  module Cli
    module Internal
      # Layer-C exception #4: user-supplied paths outside project storage.
      #
      # CLI options like `--brief PATH` or `--body-file PATH` take filesystem
      # paths from the human invoker. Those paths can point anywhere on the
      # host (absolute, relative-to-cwd, outside any `.owl/` project), so they
      # cannot be resolved through `Owl::Storage::Api` (which routes through
      # `BackendResolver` against a project root). This module is the
      # canonical place that direct `File.*` is allowed for such inputs.
      module UserFileReader
        module_function

        def read(path:)
          path_str = path.to_s
          unless File.exist?(path_str)
            return Result.err(
              code: :user_file_missing,
              message: "File not found: #{path_str}",
              details: { path: path_str }
            )
          end

          Result.ok(File.read(path_str))
        end
      end
    end
  end
end
