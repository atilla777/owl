# frozen_string_literal: true

require 'json'

require_relative '../../internal/gem_assets'
require_relative 'json_schema_walker'
require_relative 'schema_resolver'

module Owl
  module Validation
    module Internal
      module SchemaCheck
        module_function

        def schema(name)
          (@schemas ||= {})[name] ||= load_schema(name)
        end

        def walk(name, body)
          JsonSchemaWalker.validate(schema(name), body)
        end

        def reset!
          @schemas = nil
        end

        def load_schema(name)
          SchemaResolver.local_override(name) ||
            JSON.parse(Owl::Internal::GemAssets.read(File.join('schemas', name)))
        end
      end
    end
  end
end
