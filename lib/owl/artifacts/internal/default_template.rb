# frozen_string_literal: true

module Owl
  module Artifacts
    module Internal
      module DefaultTemplate
        module_function

        def render
          <<~YAML
            schema_version: 1

            artifacts: {}
          YAML
        end
      end
    end
  end
end
