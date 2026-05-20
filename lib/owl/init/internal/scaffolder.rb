# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative 'layout_files'

module Owl
  module Init
    module Internal
      module Scaffolder
        module_function

        def call(root:, force: false)
          root_path = Pathname.new(root.to_s).expand_path
          files = LayoutFiles.call(root: root_path, project_id: derive_project_id(root_path))

          created = []
          skipped = []
          files.each do |file|
            path = Pathname.new(file[:path])
            if path.exist? && !force
              skipped << path.to_s
              next
            end

            path.dirname.mkpath
            path.write(file[:contents])
            created << path.to_s
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
