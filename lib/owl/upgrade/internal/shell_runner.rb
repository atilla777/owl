# frozen_string_literal: true

require 'open3'

module Owl
  module Upgrade
    module Internal
      # Default command runner for `owl self-update`. Injectable so specs can
      # drive the orchestration without real git/gem side effects.
      module ShellRunner
        Outcome = Struct.new(:ok, :stdout, :stderr)

        module_function

        def run(cmd, chdir: nil)
          opts = chdir ? { chdir: chdir } : {}
          stdout, stderr, status = Open3.capture3(*cmd, **opts)
          Outcome.new(status.success?, stdout, stderr)
        rescue StandardError => e
          Outcome.new(false, '', e.message)
        end
      end
    end
  end
end
