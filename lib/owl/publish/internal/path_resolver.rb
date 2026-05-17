# frozen_string_literal: true

require 'pathname'

require_relative '../../result'
require_relative '../../config/api'
require_relative '../../storage/api'
require_relative '../../storage/internal/path_template'

module Owl
  module Publish
    module Internal
      module PathResolver
        SOURCE_ROLE = 'tasks'
        TARGET_ROLE = 'docs'

        module_function

        def call(root:, task_payload:, rules:)
          profile_result = load_profile(root: root)
          return profile_result if profile_result.is_a?(Owl::Result::Err)

          profile = profile_result
          vars = task_vars(task_payload)

          resolved = []
          rules.each_with_index do |rule, index|
            source = resolve(role: SOURCE_ROLE, profile: profile, root: root,
                             template: rule['from'], vars: vars, rule_index: index, key: 'from')
            return source if source.is_a?(Owl::Result::Err)

            target = resolve(role: TARGET_ROLE, profile: profile, root: root,
                             template: rule['to'], vars: vars, rule_index: index, key: 'to')
            return target if target.is_a?(Owl::Result::Err)

            resolved << {
              'from' => rule['from'],
              'to' => rule['to'],
              'source_path' => source.to_s,
              'target_path' => target.to_s
            }
          end

          Result.ok(resolved)
        end

        def resolve(role:, profile:, root:, template:, vars:, rule_index:, key:)
          base = Owl::Storage::Api.resolve(role: role, profile: profile, root: root)
          return base if base.err?

          rendered = Owl::Storage::Internal::PathTemplate.render(template.to_s, vars)
          (Pathname.new(base.value.to_s) + rendered).expand_path
        rescue Owl::Storage::Internal::PathTemplate::UnknownVariable => e
          Result.err(
            code: :publishes_unknown_variable,
            message: e.message,
            details: { rule_index: rule_index, key: key, variable: e.key, template: template.to_s }
          )
        end

        def load_profile(root:)
          config_result = Owl::Config::Api.load(root: root)
          return config_result if config_result.err?

          config_result.value.active_profile
        end

        def task_vars(task_payload)
          {
            'task' => {
              'id' => task_payload['id'].to_s,
              'slug' => task_payload['slug'].to_s
            }
          }
        end
      end
    end
  end
end
