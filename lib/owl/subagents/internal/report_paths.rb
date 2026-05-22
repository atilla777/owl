# frozen_string_literal: true

require 'pathname'

module Owl
  module Subagents
    module Internal
      # Resolves canonical filesystem paths for subagent input bundles and
      # report bodies under a project root. All paths live under
      # `.owl/local/` so they are not part of durable project state.
      module ReportPaths
        REPORT_SUBDIR = '.owl/local/reports'
        SPAWN_SUBDIR = '.owl/local/spawns'

        module_function

        def report_path(root:, task_id:, step_id:)
          Pathname.new(root.to_s).join(REPORT_SUBDIR, task_id.to_s, "#{step_id}.md")
        end

        def spawn_input_path(root:, task_id:, step_id:)
          Pathname.new(root.to_s).join(SPAWN_SUBDIR, task_id.to_s, "#{step_id}.input.yaml")
        end
      end
    end
  end
end
