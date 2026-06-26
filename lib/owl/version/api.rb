# frozen_string_literal: true

require_relative '../result'
require_relative '../version'
require_relative '../config/api'

module Owl
  module Version
    # Surfaces the two Owl versions that matter to a project:
    #
    # - `gem`     — the running gem (`Owl::VERSION`);
    # - `project` — the version stamped into `.owl/config.yaml` under
    #   `owl.version` by `owl init` / `owl upgrade` (`nil` for legacy projects
    #   initialized before stamping existed).
    #
    # They diverge when the gem is updated without re-running `owl upgrade`
    # (the canonical self-hosted case). `up_to_date` reports that drift.
    module Api
      module_function

      def info(root:)
        result = Owl::Config::Api.read_key(root: root, key: 'owl.version')
        project = result.ok? ? result.value[:value] : nil

        Result.ok(
          gem: Owl::VERSION,
          project: project,
          up_to_date: !project.nil? && project == Owl::VERSION
        )
      end
    end
  end
end
