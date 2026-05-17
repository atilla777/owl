# frozen_string_literal: true

module Owl
  module Workflows
    module Internal
      module DefaultTemplate
        module_function

        def render
          <<~YAML
            schema_version: 1

            default_workflow: feature

            workflows: {}
          YAML
        end
      end
    end
  end
end
