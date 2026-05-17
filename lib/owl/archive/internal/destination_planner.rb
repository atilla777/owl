# frozen_string_literal: true

require 'pathname'

require_relative '../../result'

module Owl
  module Archive
    module Internal
      module DestinationPlanner
        MAX_SUFFIX = 100

        module_function

        def call(archive_root:, task_id:, slug:, now:)
          root = Pathname.new(archive_root.to_s)
          date = now.utc.strftime('%Y-%m-%d')
          base = "#{date}-#{task_id}-#{slug}"

          base_path = root + base
          return ok_payload(base_path, base, nil) unless base_path.exist?

          (2..MAX_SUFFIX).each do |suffix|
            candidate_name = "#{base}-#{suffix}"
            candidate_path = root + candidate_name
            return ok_payload(candidate_path, candidate_name, suffix) unless candidate_path.exist?
          end

          Result.err(
            code: :slug_collision_limit,
            message: "Archive destination collision limit (#{MAX_SUFFIX}) exceeded for '#{base}'.",
            details: { archive_root: root.to_s, base_name: base, max_suffix: MAX_SUFFIX }
          )
        end

        def ok_payload(path, base_name, suffix)
          Result.ok(
            destination_path: path,
            base_name: base_name,
            collision_suffix: suffix
          )
        end
      end
    end
  end
end
