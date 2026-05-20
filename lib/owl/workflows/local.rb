# frozen_string_literal: true

module Owl
  module Workflows
    # Filesystem-backend-specific "local view" structures for the Workflows
    # domain. See `Owl::Tasks::Local` for the wider rationale.
    module Local
      WorkflowFile = Data.define(:source_path)
    end
  end
end
