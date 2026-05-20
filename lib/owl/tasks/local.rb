# frozen_string_literal: true

module Owl
  module Tasks
    # Filesystem-backend-specific "local view" structures for the Tasks domain.
    #
    # These value objects carry the absolute paths that `Owl::Tasks::Backends::
    # Filesystem` writes to disk (task.yaml, index.yaml, current.yaml pointer).
    # They are produced by the filesystem backend and surfaced through
    # `Owl::Tasks::Api.local_paths(...)` as a reflection method. The public
    # `Owl::Tasks::Api` payloads themselves are stripped of these path keys so
    # that non-filesystem backends can satisfy the same public contract without
    # synthesising fake paths.
    module Local
      TaskFile = Data.define(:task_path)
      Index    = Data.define(:index_path)
      Pointer  = Data.define(:pointer_path)
    end
  end
end
