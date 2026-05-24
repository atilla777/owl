# frozen_string_literal: true

require 'json'
require 'pathname'

require_relative '../../storage/internal/root_detector'

module Owl
  module Validation
    module Internal
      module SchemaResolver
        module_function

        def local_override(name, cwd: Dir.pwd)
          root = Owl::Storage::Internal::RootDetector.detect(cwd)
          return nil if root.nil?

          path = Pathname.new(root.to_s).join('.owl', 'schemas', name.to_s)
          return nil unless path.file?

          parse_override(path)
        end

        def parse_override(path)
          JSON.parse(path.read)
        rescue JSON::ParserError, SystemCallError => e
          raise RuntimeError,
                "Owl::Validation::Internal::SchemaResolver: invalid local override at #{path}: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
