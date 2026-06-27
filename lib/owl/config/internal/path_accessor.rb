# frozen_string_literal: true

module Owl
  module Config
    module Internal
      module PathAccessor
        class MissingKeyError < StandardError
        end

        class InvalidPathError < StandardError
        end

        module_function

        def split(dot_path)
          raise InvalidPathError, 'key must be a non-empty string' if dot_path.nil? || dot_path.to_s.empty?

          segments = dot_path.to_s.split('.')
          raise InvalidPathError, "key contains empty segment: #{dot_path}" if segments.any?(&:empty?)

          segments
        end

        def read(raw_hash, dot_path)
          segments = split(dot_path)

          node = raw_hash
          segments.each do |segment|
            raise MissingKeyError, "Key not present: #{dot_path}" unless node.is_a?(Hash) && node.key?(segment)

            node = node[segment]
          end
          node
        end

        def write(raw_hash, dot_path, value)
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
      end
    end
  end
end
