# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'securerandom'
require 'time'
require 'yaml'

require_relative '../../result'

module Owl
  module Tasks
    module Internal
      # Atomic, durable task lease backed by a single YAML file per task.
      #
      # Mutual exclusion is provided by POSIX `O_EXCL` ("create only if
      # absent"): the first session to create `claims/<TASK-ID>.yaml` owns the
      # lease; concurrent attempts raise `Errno::EEXIST`, which is the
      # contention signal. Unlike `flock`, the lease outlives the short-lived
      # `bin/owl` process — ownership is the file's existence plus its `expires_at`.
      module ExclusiveLease
        module_function

        # Atomically create the lease. On contention, an *expired* lease is
        # reclaimed exactly once; a live lease yields `:lease_held`.
        def acquire(path:, payload:, now:)
          target = Pathname.new(path.to_s)
          FileUtils.mkdir_p(target.dirname.to_s)
          create_exclusive(target, payload)
        rescue Errno::EEXIST
          reclaim_or_reject(target, payload, now)
        end

        # Unconditional write (steal / heartbeat). Bypasses the live-lease check.
        def replace(path:, payload:)
          target = Pathname.new(path.to_s)
          FileUtils.mkdir_p(target.dirname.to_s)
          tmp = target.dirname.join(".#{target.basename}.tmp.#{Process.pid}.#{SecureRandom.hex(4)}")
          tmp.write(YAML.dump(stringify(payload)))
          File.rename(tmp.to_s, target.to_s)
          Result.ok(payload)
        ensure
          tmp&.delete if tmp&.exist?
        end

        # Read the lease at `path`. Returns Result.ok(nil) when absent,
        # Result.ok(Hash) when present, :lease_invalid on a malformed file.
        def read(path:)
          target = Pathname.new(path.to_s)
          return Result.ok(nil) unless target.exist?

          raw = YAML.safe_load(target.read, aliases: false, permitted_classes: [Time])
          return Result.ok(raw) if raw.is_a?(Hash)

          Result.err(code: :lease_invalid, message: "Lease file is not a mapping: #{target}",
                     details: { path: target.to_s })
        rescue Psych::SyntaxError => e
          Result.err(code: :lease_invalid, message: e.message, details: { path: target.to_s })
        end

        # Delete the lease iff `token` matches the holder.
        def release(path:, token:)
          read_result = read(path: path)
          return read_result if read_result.err?

          existing = read_result.value
          return lease_not_found(path) if existing.nil?
          return lease_not_owned(path, existing, token) unless existing['claimed_by'].to_s == token.to_s

          Pathname.new(path.to_s).delete
          Result.ok(task_id: existing['task_id'], released: true)
        end

        def expired?(payload, now)
          raw = payload.is_a?(Hash) ? payload['expires_at'] : nil
          return true if raw.nil? || raw.to_s.empty?

          now >= Time.iso8601(raw.to_s)
        rescue ArgumentError
          true
        end

        def create_exclusive(target, payload)
          target.open(File::WRONLY | File::CREAT | File::EXCL) { |file| file.write(YAML.dump(stringify(payload))) }
          Result.ok(payload)
        end

        def reclaim_or_reject(target, payload, now)
          read_result = read(path: target)
          existing = read_result.ok? ? read_result.value : nil
          return lease_held(target, existing) if existing && !expired?(existing, now)

          target.delete if target.exist?
          create_exclusive(target, payload)
        rescue Errno::EEXIST
          lease_held(target, read(path: target).value)
        end

        def lease_held(target, existing)
          Result.err(code: :lease_held, message: "Task is already claimed: #{target.basename.to_s.sub('.yaml', '')}",
                     details: { path: target.to_s, existing: existing })
        end

        def lease_not_found(path)
          Result.err(code: :lease_not_found, message: "No lease at #{path}", details: { path: path.to_s })
        end

        def lease_not_owned(path, existing, token)
          Result.err(code: :lease_not_owned,
                     message: 'Lease is held by a different session token.',
                     details: { path: path.to_s, holder: existing['claimed_by'], token: token.to_s })
        end

        def stringify(value)
          case value
          when Hash then value.each_with_object({}) { |(k, v), memo| memo[k.to_s] = stringify(v) }
          when Array then value.map { |v| stringify(v) }
          else value
          end
        end
      end
    end
  end
end
