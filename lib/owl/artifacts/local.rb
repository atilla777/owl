# frozen_string_literal: true

module Owl
  module Artifacts
    # Filesystem-backend-specific "local view" structures for the Artifacts
    # domain. See `Owl::Tasks::Local` for the wider rationale.
    module Local
      ArtifactType = Data.define(:source_path, :template_path)
    end
  end
end
