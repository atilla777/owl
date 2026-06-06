# frozen_string_literal: true

require_relative '../../result'
require_relative '../../config/api'
require_relative '../../storage/api'

module Owl
  module Specs
    module Internal
      # Locates and reads project-level, domain-addressed specs under the
      # `specs` storage role. Each spec lives at `specs/<domain>/spec.md`.
      #
      # Domain inputs are slug-validated (`/\A[a-z0-9][a-z0-9_-]*\z/`) BEFORE any
      # path resolution, so `..`/slashes can never escape the role directory.
      #
      # All filesystem access is funneled through `Owl::Storage::Api`
      # (`resolve`, `children`, `read`, `exists?`) — no direct
      # `File`/`Dir`/`Pathname` I/O lives here (constitution §5.10, docs/agents/27).
      module SpecLocator
        DOMAIN_PATTERN = /\A[a-z0-9][a-z0-9_-]*\z/
        SPEC_FILENAME = 'spec.md'

        module_function

        def validate_domain(domain)
          domain_str = domain.to_s
          return Result.ok(domain_str) if domain_str.match?(DOMAIN_PATTERN)

          Result.err(
            code: :invalid_domain,
            message: "Domain '#{domain_str}' is not a valid slug (expected /\\A[a-z0-9][a-z0-9_-]*\\z/).",
            details: { domain: domain_str }
          )
        end

        def dir(root:)
          config_result = Owl::Config::Api.load(root: root)
          return config_result if config_result.err?

          profile = config_result.value.active_profile
          Owl::Storage::Api.resolve(role: 'specs', profile: profile, root: root)
        end

        def path(root:, domain:)
          valid = validate_domain(domain)
          return valid if valid.err?

          base = dir(root: root)
          return base if base.err?

          Result.ok(domain: valid.value, path: spec_file(base.value, valid.value))
        end

        def list(root:)
          base = dir(root: root)
          return base if base.err?

          entries = Owl::Storage::Api.children(path: base.value).value
                                     .select { |child| Owl::Storage::Api.exists?(path: child_spec(child)) }
                                     .map { |child| { domain: child.basename.to_s, path: child_spec(child) } }
                                     .sort_by { |entry| entry[:domain] }
          Result.ok(entries)
        end

        def read(root:, domain:)
          located = path(root: root, domain: domain)
          return located if located.err?

          spec_path = located.value[:path]
          unless Owl::Storage::Api.exists?(path: spec_path)
            return spec_not_found(root: root, domain: located.value[:domain])
          end

          body = Owl::Storage::Api.read(path: spec_path)
          return body if body.err?

          Result.ok(domain: located.value[:domain], path: spec_path, body: body.value)
        end

        def available_domains(root:)
          result = list(root: root)
          return [] if result.err?

          result.value.map { |entry| entry[:domain] }
        end

        def spec_not_found(root:, domain:)
          Result.err(
            code: :spec_not_found,
            message: "No spec found for domain '#{domain}'.",
            details: { domain: domain, available: available_domains(root: root) }
          )
        end

        def spec_file(base, domain)
          "#{base}/#{domain}/#{SPEC_FILENAME}"
        end

        def child_spec(child)
          "#{child}/#{SPEC_FILENAME}"
        end
      end
    end
  end
end
