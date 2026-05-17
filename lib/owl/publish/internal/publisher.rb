# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'time'

require_relative '../../result'

module Owl
  module Publish
    module Internal
      module Publisher
        module_function

        def call(resolved_rules:, dry_run:, now: Time.now.utc)
          timestamp = now.utc.strftime('%Y%m%dT%H%M%SZ')

          results = []
          resolved_rules.each_with_index do |rule, index|
            outcome = process_rule(rule: rule, index: index, timestamp: timestamp, dry_run: dry_run)
            return outcome if outcome.is_a?(Owl::Result::Err)

            results << outcome
          end

          Result.ok(results)
        end

        def process_rule(rule:, index:, timestamp:, dry_run:)
          source = Pathname.new(rule['source_path'])
          target = Pathname.new(rule['target_path'])

          unless source.exist?
            return Result.err(
              code: :source_missing,
              message: "Source artifact does not exist: #{source}",
              details: { rule_index: index, from: rule['from'], source_path: source.to_s }
            )
          end

          action = target.exist? ? 'replaced' : 'created'
          return build_result(rule: rule, action: action, backup_path: nil, dry_run: true) if dry_run

          write_rule(rule: rule, source: source, target: target, action: action,
                     timestamp: timestamp, index: index)
        end

        def write_rule(rule:, source:, target:, action:, timestamp:, index:)
          backup_path = nil

          if action == 'replaced'
            backup_path = backup_path_for(target: target, timestamp: timestamp)
            backup_err = create_backup(target: target, backup_path: backup_path, index: index)
            return backup_err if backup_err
          end

          write_err = copy_to_target(source: source, target: target, backup_path: backup_path, index: index)
          return write_err if write_err

          build_result(rule: rule, action: action, backup_path: backup_path, dry_run: false)
        end

        def create_backup(target:, backup_path:, index:)
          FileUtils.copy_file(target.to_s, backup_path.to_s)
          nil
        rescue StandardError => e
          Result.err(
            code: :backup_failed,
            message: "Failed to create backup '#{backup_path}': #{e.message}",
            details: { rule_index: index, target_path: target.to_s,
                       backup_path: backup_path.to_s, error_class: e.class.name }
          )
        end

        def copy_to_target(source:, target:, backup_path:, index:)
          FileUtils.mkdir_p(target.dirname.to_s)
          target.write(source.read)
          nil
        rescue StandardError => e
          Result.err(
            code: :write_failed,
            message: "Failed to write target '#{target}': #{e.message}",
            details: { rule_index: index, target_path: target.to_s,
                       backup_path: backup_path&.to_s, error_class: e.class.name }
          )
        end

        def backup_path_for(target:, timestamp:)
          Pathname.new("#{target}.bak.#{timestamp}")
        end

        def build_result(rule:, action:, backup_path:, dry_run:)
          {
            'from' => rule['from'],
            'to' => rule['to'],
            'source_path' => rule['source_path'],
            'target_path' => rule['target_path'],
            'action' => action,
            'backup_path' => backup_path&.to_s,
            'dry_run' => dry_run
          }
        end
      end
    end
  end
end
