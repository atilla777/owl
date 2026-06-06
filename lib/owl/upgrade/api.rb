# frozen_string_literal: true

require_relative 'internal/refresh'
require_relative 'internal/self_update'

module Owl
  module Upgrade
    # Facade for keeping Owl current:
    #   * `refresh` — provenance-aware refresh of a project's copied seed content
    #     (skills/commands, managed workflow/artifact files, registry merge),
    #     preserving project-owned content. Run per-project after a gem update.
    #   * `self_update` — update the owl-cli gem itself from github main.
    module Api
      module_function

      def refresh(root:, dry_run: false, backup: true, targets: nil)
        Internal::Refresh.call(root: root, dry_run: dry_run, backup: backup, targets: targets)
      end

      def self_update(check: false, runner: Internal::ShellRunner)
        Internal::SelfUpdate.call(check: check, runner: runner)
      end
    end
  end
end
