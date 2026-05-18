# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../../../result'
require_relative '../current_pointer'

module Owl
  module Tasks
    module Internal
      module Archive
        module CurrentResetter
          module_function

          def reset_if_matches(local_state_root:, task_id:)
            path = Owl::Tasks::Internal::CurrentPointer.pointer_path(local_state_root: local_state_root)
            return no_reset(path) unless path.exist?

            raw = YAML.safe_load(path.read, aliases: false, permitted_classes: [Time])
            return no_reset(path) unless raw.is_a?(Hash) && raw['task_id'].to_s == task_id.to_s

            previous_bytes = path.read
            path.delete
            Result.ok(reset: true, path: path.to_s, previous_bytes: previous_bytes)
          rescue Psych::SyntaxError
            no_reset(path)
          end

          def no_reset(path)
            Result.ok(reset: false, path: path.to_s, previous_bytes: nil)
          end

          def restore(path:, previous_bytes:)
            return if previous_bytes.nil?

            Pathname.new(path).write(previous_bytes)
          end
        end
      end
    end
  end
end
