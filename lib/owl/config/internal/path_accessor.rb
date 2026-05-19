# frozen_string_literal: true

module Owl
  module Config
    module Internal
      module PathAccessor
        SUPPORTED_ROOT = 'settings'

        UnsupportedPathError = Class.new(StandardError)
        MissingKeyError = Class.new(StandardError)
        InvalidPathError = Class.new(StandardError)

        module_function

        def supported?(dot_path)
          segments = split(dot_path)
          segments.first == SUPPORTED_ROOT
        end

        def split(dot_path)
          raise InvalidPathError, 'key must be a non-empty string' if dot_path.nil? || dot_path.to_s.empty?

          segments = dot_path.to_s.split('.')
          raise InvalidPathError, "key contains empty segment: #{dot_path}" if segments.any?(&:empty?)

          segments
        end

        def read(raw_hash, dot_path)
          ensure_supported!(dot_path)
          segments = split(dot_path)

          node = raw_hash
          segments.each do |segment|
            unless node.is_a?(Hash) && node.key?(segment)
              raise MissingKeyError, "Key not present: #{dot_path}"
            end

            node = node[segment]
          end
          node
        end

        def write(raw_hash, dot_path, value)
          ensure_supported!(dot_path)
          segments = split(dot_path)

          node = raw_hash
          segments[0..-2].each do |segment|
            existing = node[segment]
            if existing.nil?
              node[segment] = {}
            elsif !existing.is_a?(Hash)
              raise InvalidPathError,
                    "Cannot descend into #{dot_path}: '#{segment}' is not a mapping"
            end
            node = node[segment]
          end
          node[segments.last] = value
          raw_hash
        end

        def ensure_supported!(dot_path)
          return if supported?(dot_path)

          raise UnsupportedPathError,
                "Only paths under '#{SUPPORTED_ROOT}.*' are supported via config get/set; got: #{dot_path}"
        end
      end
    end
  end
end
