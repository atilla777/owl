# frozen_string_literal: true

require 'optparse'
require 'pathname'

require_relative '../../../artifacts/api'
require_relative '../../../config/api'
require_relative '../../../storage/api'
require_relative '../../../workflows/api'
require_relative '../json_printer'

module Owl
  module Cli
    module Internal
      module Commands
        module ConfigValidate
          module_function

          def run(argv:, stdout:, stderr:, cwd:, env: ENV.to_h) # rubocop:disable Lint/UnusedMethodArgument
            options = parse_options(argv)
            root_result = resolve_root(options[:root], cwd, stderr: stderr)
            return root_result if root_result.is_a?(Integer)

            root = root_result
            config_result = Owl::Config::Api.validate(root: root)
            workflows_result = Owl::Workflows::Api.list(root: root)
            artifacts_result = Owl::Artifacts::Api.list(root: root)

            valid = config_result.ok? && workflows_result.ok? && artifacts_result.ok?
            errors = []
            errors.concat(extract_errors(:config, config_result))
            errors.concat(extract_errors(:workflows, workflows_result))
            errors.concat(extract_errors(:artifacts, artifacts_result))

            payload = build_payload(
              root: root,
              valid: valid,
              config_result: config_result,
              workflows_result: workflows_result,
              artifacts_result: artifacts_result,
              errors: errors
            )

            JsonPrinter.success(stdout, payload)
          rescue OptionParser::ParseError => e
            JsonPrinter.failure(stderr, code: :invalid_arguments, message: e.message)
          end

          def parse_options(argv)
            options = { root: nil }
            parser = OptionParser.new do |opts|
              opts.banner = 'Usage: owl config validate [--root PATH] [--json]'
              opts.on('--root PATH', String, 'Project root (default: auto-detect from cwd)') { |v| options[:root] = v }
              opts.on('--json', 'Force JSON output (default)') { options[:json] = true }
            end
            parser.parse!(argv)
            options
          end

          def resolve_root(explicit_root, cwd, stderr:)
            if explicit_root
              Pathname.new(explicit_root).expand_path
            else
              detect_result = Owl::Storage::Api.detect_root(start: cwd)
              if detect_result.err?
                return JsonPrinter.failure(stderr, code: detect_result.code, message: detect_result.message,
                                                   details: detect_result.details)
              end

              detect_result.value
            end
          end

          def extract_errors(scope, result)
            return [] if result.ok?

            details = result.details || {}
            nested = details[:errors] || details['errors']
            if nested.is_a?(Array)
              nested.map { |e| e.merge(scope: scope) }
            else
              [{ scope: scope, code: result.code, message: result.message, details: details }]
            end
          end

          def build_payload(root:, valid:, config_result:, workflows_result:, artifacts_result:, errors:)
            document = config_result.ok? ? config_result.value : extract_document(config_result)
            schema_version = document&.schema_version
            project = document&.project
            active_profile = document ? safe_active_profile_name(document) : nil
            roles_present = document ? safe_roles_present(document) : []

            {
              ok: valid,
              valid: valid,
              root: root.to_s,
              schema_version: schema_version,
              project: project,
              storage: {
                active_profile: active_profile,
                roles_present: roles_present
              },
              workflows: workflows_summary(workflows_result),
              artifacts: artifacts_summary(artifacts_result),
              errors: errors
            }
          end

          def extract_document(result)
            details = result.details || {}
            details[:document] || details['document']
          end

          def safe_active_profile_name(document)
            document.storage['active_profile']
          end

          def safe_roles_present(document)
            profile_name = document.storage['active_profile']
            profile = (document.storage['profiles'] || {})[profile_name.to_s]
            ((profile && profile['roles']) || {}).keys
          end

          def workflows_summary(result)
            if result.ok?
              entries = result.value
              { count: entries.length, keys: entries.map { |e| e[:key] } }
            else
              { count: 0, keys: [], error: { code: result.code, message: result.message } }
            end
          end

          def artifacts_summary(result)
            if result.ok?
              entries = result.value
              { count: entries.length, keys: entries.map { |e| e[:key] } }
            else
              { count: 0, keys: [], error: { code: result.code, message: result.message } }
            end
          end
        end
      end
    end
  end
end
