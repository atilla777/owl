# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative '../../storage/internal/filesystem_backend'
require_relative 'layout_files'

module Owl
  module Init
    module Internal
      # Layer-C exception #5: bootstrap write before BackendResolver can route.
      # `owl init` creates the first `.owl/config.yaml`, so at the moment of
      # this call BackendResolver cannot route through the config backend yet —
      # scaffolder writes directly through `Owl::Storage::Internal::FilesystemBackend`,
      # bypassing `Owl::Storage::Api` (which would try to resolve a backend
      # against `.owl/config.yaml` and fail).
      module Scaffolder
        module_function

        def call(root:, force: false)
          root_path = Pathname.new(root.to_s).expand_path
          files = LayoutFiles.call(root: root_path, project_id: derive_project_id(root_path))

          created = []
          skipped = []
          files.each do |file|
            path = file[:path].to_s
            if Owl::Storage::Internal::FilesystemBackend.exists?(path) && !force
              skipped << path
              next
            end

            Owl::Storage::Internal::FilesystemBackend.write(path: path, contents: file[:contents])
            created << path
          end

          Owl::Result.ok(root: root_path.to_s, created: created, skipped: skipped)
        end

        def derive_project_id(root_path)
          root_path.basename.to_s
        end
      end
    end
  end
end
