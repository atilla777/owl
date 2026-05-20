# frozen_string_literal: true

require 'json'

require_relative '../../internal/gem_assets'
require_relative 'json_schema_walker'

module Owl
  module Validation
    module Internal
      module SchemaCheck
        module_function

        def schema(name)
          (@schemas ||= {})[name] ||=
            JSON.parse(Owl::Internal::GemAssets.read(File.join('schemas', name)))
        end

        def walk(name, body)
          JsonSchemaWalker.validate(schema(name), body)
        end
      end
    end
  end
end
