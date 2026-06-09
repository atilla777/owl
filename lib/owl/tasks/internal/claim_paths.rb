# frozen_string_literal: true

require 'pathname'

module Owl
  module Tasks
    module Internal
      # Filesystem layout for per-task claim leases. Each claim is a single
      # YAML file under `<local_state>/claims/<TASK-ID>.yaml`, owned by the
      # session that created it via O_EXCL (see ExclusiveLease).
      module ClaimPaths
        CLAIMS_SUBDIR = 'claims'
        DEFAULT_TTL_SECONDS = 600
        SCHEMA_VERSION = 1

        module_function

        def claims_dir(local_state_root:)
          Pathname.new(local_state_root.to_s).join(CLAIMS_SUBDIR)
        end

        def claim_path(local_state_root:, task_id:)
          claims_dir(local_state_root: local_state_root).join("#{task_id}.yaml")
        end
      end
    end
  end
end
