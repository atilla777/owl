# frozen_string_literal: true

module Owl
  module Storage
    module Internal
      module PathTemplate
        PLACEHOLDER = /\{\{\s*([a-z][a-z0-9_.]*)\s*\}\}/i

        module_function

        def render(template, vars)
          template.to_s.gsub(PLACEHOLDER) do
            key = Regexp.last_match(1)
            resolve(key, vars) or raise UnknownVariable.new(key, template)
          end
        end

        def resolve(key, vars)
          parts = key.split('.')
          parts.reduce(vars) do |scope, part|
            return nil unless scope.is_a?(Hash)

            value = scope[part] || scope[part.to_sym]
            return nil if value.nil?

            value
          end&.to_s
        end

        class UnknownVariable < StandardError
          attr_reader :key, :template

          def initialize(key, template)
            @key = key
            @template = template
            super("Unknown placeholder {{#{key}}} in path template: #{template}")
          end
        end
      end
    end
  end
end
