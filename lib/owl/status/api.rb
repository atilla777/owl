# frozen_string_literal: true

require_relative 'internal/builder'

module Owl
  module Status
    module Api
      module_function

      def show(root:, task_id: nil)
        Internal::Builder.call(root: root, task_id: task_id)
      end
    end
  end
end
