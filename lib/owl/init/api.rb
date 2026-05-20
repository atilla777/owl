# frozen_string_literal: true

require_relative 'internal/scaffolder'

module Owl
  module Init
    module Api
      module_function

      def scaffold(root:, force: false)
        Internal::Scaffolder.call(root: root, force: force)
      end
    end
  end
end
