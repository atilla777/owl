# frozen_string_literal: true

require 'pathname'

require_relative '../../../result'

module Owl
  module Tasks
    module Internal
      module Archive
        # Private wrapper around Pathname#rename that returns Owl::Result.
        # Lives in backend internals (no public Storage::Api callers) and is
        # the test seam previously provided by Owl::Storage::Api.rename.
        module PathRename
          module_function

          def call(source:, dest:)
            Pathname.new(source.to_s).rename(dest.to_s)
            Result.ok(source: Pathname.new(source.to_s), dest: Pathname.new(dest.to_s))
          rescue SystemCallError => e
            Result.err(
              code: :rename_failed,
              message: "Failed to rename '#{source}' to '#{dest}': #{e.message}",
              details: {
                source: source.to_s,
                dest: dest.to_s,
                reason: e.message,
                error_class: e.class.name
              }
            )
          end
        end
      end
    end
  end
end
