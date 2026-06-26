# frozen_string_literal: true

require 'pathname'

module Owl
  module Workflows
    module Internal
      # Path helpers for the filesystem workflows backend: canonical on-disk
      # locations under `.owl/` plus the directory-containment guard shared by
      # the per-step context read/write paths.
      module Paths
        module_function

        def workflow_source_path(root:, id:)
          Pathname.new(root.to_s) + '.owl' + 'workflows' + id.to_s + 'workflow.yaml'
        end

        def registry_path(root:)
          Pathname.new(root.to_s) + '.owl' + 'workflows.yaml'
        end

        def within?(base_dir:, resolved:)
          base_str = base_dir.to_s
          resolved_str = resolved.to_s
          return true if resolved_str == base_str

          resolved_str.start_with?("#{base_str}#{File::SEPARATOR}")
        end
      end
    end
  end
end
