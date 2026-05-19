# frozen_string_literal: true

require 'pathname'

module Owl
  module Context
    module Internal
      module FilesystemSource
        module_function

        # Roughly ~2K tokens worth of UTF-8 markdown. Beyond this we still
        # return the overlay but flag it so callers can surface a warning.
        WARNING_THRESHOLD_BYTES = 8 * 1024

        # Reads all overlay files at the given paths. Skips missing files
        # and files whose content is empty after stripping whitespace.
        def read_all(paths:)
          paths.filter_map { |path| read_one(path) }
        end

        def read_one(path)
          return nil unless path.file?

          body = path.read
          return nil if body.strip.empty?

          {
            source: path.to_s,
            body: body,
            warning: body.bytesize > WARNING_THRESHOLD_BYTES ? :too_long : nil
          }
        end

        private_class_method :read_one
      end
    end
  end
end
