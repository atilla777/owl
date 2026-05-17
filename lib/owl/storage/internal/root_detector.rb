# frozen_string_literal: true

require 'pathname'

module Owl
  module Storage
    module Internal
      module RootDetector
        CONTROL_DIR = '.owl'

        module_function

        def detect(start)
          start_path = Pathname.new(start.to_s).expand_path
          current = start_path

          loop do
            return current if (current + CONTROL_DIR).directory?

            parent = current.parent
            return nil if parent == current

            current = parent
          end
        end
      end
    end
  end
end
