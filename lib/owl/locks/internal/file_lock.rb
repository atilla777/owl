# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'securerandom'
require 'time'
require 'yaml'

require_relative '../../result'

module Owl
  module Locks
    module Internal
      # Repo-scoped advisory lock backed by a single YAML file created with
      # POSIX `O_EXCL` ("create only if absent"). This is a deliberate, self-
      # contained copy of the Tasks `ExclusiveLease` mechanism so the Locks
      # domain does not reach across into Tasks internals for one primitive.
      #
      # A live (unexpired) lock yields `:lock_held` (recoverable); an expired
      # lock is reclaimed exactly once. `steal: true` overwrites unconditionally.
      module FileLock
        module_function

        LOCK_SUFFIX = '.lock'
        SCHEMA_VERSION = 1

        def acquire(local_state_root:, name:, ttl:, token:, steal:, now:)
          path = lock_path(local_state_root: local_state_root, name: name)
          resolved_token = blank?(token) ? SecureRandom.uuid : token.to_s
          payload = build_payload(name: name, token: resolved_token, ttl: ttl, now: now)
          written = steal ? replace(path, payload) : create_or_reclaim(path, payload, now)
          return written if written.err?

          Result.ok(name: name.to_s, token: resolved_token, expires_at: payload['expires_at'], ttl_seconds: ttl)
        end

        def release(local_state_root:, name:, token:)
          path = lock_path(local_state_root: local_state_root, name: name)
          existing = read(path)
          return existing if existing.err?

          raw = existing.value
          return not_found(name) if raw.nil?
          return not_owned(name, raw, token) unless raw['token'].to_s == token.to_s

          File.delete(path.to_s)
          Result.ok(name: name.to_s, released: true)
        end

        def lock_path(local_state_root:, name:)
          Pathname.new(local_state_root.to_s).join("#{name}#{LOCK_SUFFIX}")
        end

        def create_or_reclaim(path, payload, now)
          FileUtils.mkdir_p(path.dirname.to_s)
          create_exclusive(path, payload)
        rescue Errno::EEXIST
          reclaim_or_reject(path, payload, now)
        end

        def reclaim_or_reject(path, payload, now)
          existing = read(path).value
          return held(path, existing) if existing && !expired?(existing, now)

          path.delete if path.exist?
          create_exclusive(path, payload)
        rescue Errno::EEXIST
          held(path, read(path).value)
        end

        def create_exclusive(path, payload)
          path.open(File::WRONLY | File::CREAT | File::EXCL) { |file| file.write(YAML.dump(stringify(payload))) }
          Result.ok(payload)
        end

        def replace(path, payload)
          FileUtils.mkdir_p(path.dirname.to_s)
          tmp = path.dirname.join(".#{path.basename}.tmp.#{Process.pid}.#{SecureRandom.hex(4)}")
          tmp.write(YAML.dump(stringify(payload)))
          File.rename(tmp.to_s, path.to_s)
          Result.ok(payload)
        ensure
          tmp&.delete if tmp&.exist?
        end

        def read(path)
          return Result.ok(nil) unless path.exist?

          raw = YAML.safe_load(path.read, aliases: false, permitted_classes: [Time])
          return Result.ok(raw) if raw.is_a?(Hash)

          Result.err(code: :lock_invalid, message: "Lock file is not a mapping: #{path}", details: { path: path.to_s })
        rescue Psych::SyntaxError => e
          Result.err(code: :lock_invalid, message: e.message, details: { path: path.to_s })
        end

        def expired?(payload, now)
          raw = payload.is_a?(Hash) ? payload['expires_at'] : nil
          return true if raw.nil? || raw.to_s.empty?

          now >= Time.iso8601(raw.to_s)
        rescue ArgumentError
          true
        end

        def build_payload(name:, token:, ttl:, now:)
          stamp = now.utc.iso8601
          {
            'schema_version' => SCHEMA_VERSION,
            'name' => name.to_s,
            'token' => token,
            'acquired_at' => stamp,
            'expires_at' => (now + ttl).utc.iso8601,
            'ttl_seconds' => ttl
          }
        end

        def held(path, existing)
          Result.err(
            code: :lock_held,
            message: "Lock is already held: #{path.basename.to_s.sub(LOCK_SUFFIX, '')}",
            details: { path: path.to_s, existing: existing },
            error_class: :recoverable
          )
        end

        def not_found(name)
          Result.err(code: :lock_not_found, message: "No lock named '#{name}'.", details: { name: name.to_s })
        end

        def not_owned(name, existing, token)
          Result.err(
            code: :lock_not_owned,
            message: 'Lock is held by a different token.',
            details: { name: name.to_s, holder: existing['token'], token: token.to_s }
          )
        end

        def blank?(value)
          value.nil? || value.to_s.empty?
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
