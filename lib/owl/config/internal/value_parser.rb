# frozen_string_literal: true

require 'json'

module Owl
  module Config
    module Internal
      module ValueParser
        module_function

        def parse(raw)
          return raw unless raw.is_a?(String)

          stripped = raw.strip

          return stripped if stripped.empty?

          return parse_json(stripped) if stripped.start_with?('[', '{')

          case stripped
          when 'true' then true
          when 'false' then false
          when /\A-?\d+\z/ then Integer(stripped)
          else stripped
          end
        end

        def parse_json(stripped)
          JSON.parse(stripped)
        rescue JSON::ParserError => e
          raise Owl::Config::Internal::ValueParser::InvalidJsonError,
                "Invalid JSON literal: #{e.message}"
        end

        class InvalidJsonError < StandardError; end
      end
    end
  end
end
