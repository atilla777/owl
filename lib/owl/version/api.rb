# frozen_string_literal: true

require_relative '../result'
require_relative '../version'
require_relative '../config/api'
require_relative 'internal/self_hosted'

module Owl
  module Version
    # Surfaces the two Owl versions that matter to a project:
    #
    # - `gem`     — the running gem (`Owl::VERSION`);
    # - `project` — the version stamped into `.owl/config.yaml` under
    #   `owl.version` by `owl init` / `owl upgrade` (`nil` for legacy projects
    #   initialized before stamping existed).
    #
    # In a consumer project these diverge when the gem is updated without
    # re-running `owl upgrade`, and `up_to_date` reports that drift. In the Owl
    # self-hosted source repository the stamp legitimately lags `Owl::VERSION`
    # (it is only refreshed by `owl upgrade` against itself), so we detect that
    # case, treat `Owl::VERSION` as authoritative for `project`, flag
    # `self_hosted: true` and report `up_to_date: true`. `info` is read-only and
    # never writes to `.owl/config.yaml`.
    module Api
      module_function

      def info(root:)
        if Owl::Version::Internal::SelfHosted.detect(root: root)
          return Result.ok(
            gem: Owl::VERSION,
            project: Owl::VERSION,
            self_hosted: true,
            up_to_date: true
          )
        end

        result = Owl::Config::Api.read_key(root: root, key: 'owl.version')
        project = result.ok? ? result.value[:value] : nil

        Result.ok(
          gem: Owl::VERSION,
          project: project,
          self_hosted: false,
          up_to_date: !project.nil? && project == Owl::VERSION
        )
      end
    end
  end
end
