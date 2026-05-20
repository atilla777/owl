# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative '../backend'
require_relative '../internal/filesystem_backend'
require_relative '../internal/path_template'
require_relative '../internal/root_detector'

module Owl
  module Storage
    module Backends
      class Filesystem
        include Owl::Storage::Backend

        def initialize(root:)
          @root = root
        end

        def read(path:)
          Result.ok(Internal::FilesystemBackend.read(path))
        rescue Errno::ENOENT => e
          Result.err(code: :file_not_found, message: e.message, details: { path: path.to_s })
        end

        def write(path:, contents:)
          Result.ok(Internal::FilesystemBackend.write(path: path, contents: contents))
        end

        def mkdir_p(path:)
          Result.ok(Internal::FilesystemBackend.mkdir_p(path))
        end

        def exists?(path:)
          Internal::FilesystemBackend.exists?(path)
        end

        def resolve(role:, profile:, vars: {})
          role_key = role.to_s
          roles = profile_roles(profile)

          unless roles.key?(role_key)
            return Result.err(
              code: :unknown_role,
              message: "Role '#{role_key}' is not defined in the active storage profile",
              details: { role: role_key, available: roles.keys }
            )
          end

          template = roles.fetch(role_key).fetch('path')
          merged_vars = build_vars(extra: vars)

          rendered = Internal::PathTemplate.render(template, merged_vars)
          Result.ok(Pathname.new(rendered).expand_path)
        rescue Internal::PathTemplate::UnknownVariable => e
          Result.err(
            code: :unknown_path_variable,
            message: e.message,
            details: { role: role_key, template: template, key: e.key }
          )
        end

        # Layer-C bootstrap exception: detect_root operates before any backend
        # selection, so the bound `@root` is intentionally ignored here.
        def detect_root(start:)
          detected = Internal::RootDetector.detect(start)

          if detected.nil?
            return Result.err(
              code: :project_root_not_found,
              message: "No .owl/ directory found walking up from #{start}",
              details: { start: start.to_s }
            )
          end

          Result.ok(detected)
        end

        private

        def profile_roles(profile)
          roles = profile.is_a?(Hash) ? (profile['roles'] || profile[:roles]) : nil
          roles ||= {}

          normalized = {}
          roles.each do |key, value|
            normalized[key.to_s] = value.is_a?(Hash) ? stringify(value) : value
          end
          normalized
        end

        def stringify(hash)
          hash.each_with_object({}) { |(k, v), memo| memo[k.to_s] = v }
        end

        def build_vars(extra:)
          base = {
            'project' => { 'root' => @root.to_s },
            'cwd' => Dir.pwd
          }

          env_vars = ENV.each_with_object({}) { |(k, v), memo| memo[k] = v }
          base['env'] = env_vars

          deep_merge(base, normalize_vars(extra))
        end

        def normalize_vars(vars)
          return {} if vars.nil? || vars.empty?

          vars.each_with_object({}) do |(k, v), memo|
            memo[k.to_s] = v.is_a?(Hash) ? normalize_vars(v) : v
          end
        end

        def deep_merge(left, right)
          left.merge(right) do |_, l_val, r_val|
            if l_val.is_a?(Hash) && r_val.is_a?(Hash)
              deep_merge(l_val, r_val)
            else
              r_val
            end
          end
        end
      end
    end
  end
end
