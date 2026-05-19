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

        # Strips HTML-comment-only stubs (the init template) so seeded
        # placeholders don't pollute step context until the user adds
        # real content beneath them.
        HTML_COMMENT_PATTERN = /<!--.*?-->/m

        def read_one(path)
          return nil unless path.file?

          body = path.read
          return nil if effectively_empty?(body)

          {
            source: path.to_s,
            body: body,
            warning: body.bytesize > WARNING_THRESHOLD_BYTES ? :too_long : nil
          }
        end

        def effectively_empty?(body)
          body.gsub(HTML_COMMENT_PATTERN, '').strip.empty?
        end

        private_class_method :read_one, :effectively_empty?

        private_class_method :read_one
      end
    end
  end
end
