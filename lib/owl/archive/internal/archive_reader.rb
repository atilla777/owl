# frozen_string_literal: true

require 'yaml'

require_relative '../../result'
require_relative '../../config/api'
require_relative '../../storage/api'

module Owl
  module Archive
    module Internal
      # Read-only reader over the archive storage role.
      #
      # Archived tasks live in directories named
      # `<YYYY-MM-DD>-<TASK-ID>-<slug>[-<collision_suffix>]/` under the
      # `archive` storage role. This module enumerates them, resolves one by
      # embedded TASK-ID (newest-wins on collisions), and reads back the
      # archived `task.yaml` payload and artifact bodies. It never moves,
      # writes, or deletes anything.
      #
      # All filesystem access is funneled through `Owl::Storage::Api`
      # (`resolve`, `children`, `read`) so no direct `File`/`Dir`/`Pathname`
      # I/O lives in this domain (see docs/agents/27 §7, §4).
      module ArchiveReader
        DIR_PATTERN = /\A(?<date>\d{4}-\d{2}-\d{2})-(?<task_id>TASK-\d+)-(?<slug>.+)\z/

        module_function

        def list(root:)
          base = resolve_archive_root(root: root)
          return base if base.err?

          Result.ok(archived: archived_entries(base.value).map { |entry| entry_summary(entry) })
        end

        def show(root:, task_id:)
          base = resolve_archive_root(root: root)
          return base if base.err?

          dir = find_dir(base.value, task_id)
          return task_not_found(base.value, task_id) if dir.nil?

          payload = read_task_yaml(dir)
          Result.ok(
            task_id: task_id,
            title: payload['title'],
            workflow_key: payload.dig('workflow', 'key'),
            status: payload['status'],
            steps: steps_summary(payload),
            artifacts: artifact_inventory(dir, payload),
            path: dir.to_s
          )
        end

        def read(root:, task_id:, artifact_key:)
          base = resolve_archive_root(root: root)
          return base if base.err?

          dir = find_dir(base.value, task_id)
          return task_not_found(base.value, task_id) if dir.nil?

          artifacts = artifact_inventory(dir, read_task_yaml(dir))
          match = artifacts.find { |artifact| artifact[:key] == artifact_key }
          return artifact_not_found(task_id, artifact_key, artifacts) if match.nil?

          body = Owl::Storage::Api.read(path: match[:path])
          return body if body.err?

          Result.ok(task_id: task_id, artifact_key: artifact_key, path: match[:path], body: body.value)
        end

        def resolve_archive_root(root:)
          config_result = Owl::Config::Api.load(root: root)
          return config_result if config_result.err?

          profile = config_result.value.active_profile
          Owl::Storage::Api.resolve(role: 'archive', profile: profile, root: root)
        end

        def archived_entries(base)
          matched = entries(base).select(&:directory?).filter_map do |child|
            match = DIR_PATTERN.match(child.basename.to_s)
            next nil unless match

            { dir: child, date: match[:date], task_id: match[:task_id], slug: match[:slug] }
          end
          matched.sort_by { |entry| entry[:dir].basename.to_s }
        end

        def find_dir(base, task_id)
          matches = archived_entries(base).select { |entry| entry[:task_id] == task_id }
          return nil if matches.empty?

          matches.max_by { |entry| entry[:dir].basename.to_s }[:dir]
        end

        def entry_summary(entry)
          payload = read_task_yaml(entry[:dir])
          {
            task_id: entry[:task_id],
            slug: entry[:slug],
            archived_date: entry[:date],
            title: payload['title'],
            parent_id: payload['parent_id'],
            path: entry[:dir].to_s
          }
        end

        def read_task_yaml(dir)
          task_file = entries(dir).find { |child| child.basename.to_s == 'task.yaml' }
          return {} if task_file.nil?

          result = Owl::Storage::Api.read(path: task_file)
          return {} if result.err?

          YAML.safe_load(result.value, aliases: false, permitted_classes: [Time]) || {}
        end

        def steps_summary(payload)
          steps = payload['steps']
          return [] unless steps.is_a?(Array)

          steps.map { |step| { id: step['id'], status: step['status'] } }
        end

        def artifact_inventory(dir, payload)
          from_map = artifacts_from_map(dir, payload)
          return from_map unless from_map.empty?

          artifacts_from_files(dir)
        end

        def artifacts_from_map(dir, payload)
          map = payload['artifacts']
          return [] unless map.is_a?(Hash) && !map.empty?

          map.map { |key, rel| { key: key.to_s, path: "#{dir}/#{rel}" } }
        end

        def artifacts_from_files(dir)
          entries(dir)
            .select { |child| child.file? && child.extname == '.md' }
            .sort_by { |child| child.basename.to_s }
            .map { |child| { key: child.basename('.md').to_s, path: child.to_s } }
        end

        def entries(dir)
          Owl::Storage::Api.children(path: dir).value
        end

        def task_not_found(base, task_id)
          Result.err(
            code: :archived_task_not_found,
            message: "No archived task '#{task_id}' found under the archive storage role.",
            details: { task_id: task_id, available_ids: archived_entries(base).map { |entry| entry[:task_id] }.uniq }
          )
        end

        def artifact_not_found(task_id, artifact_key, artifacts)
          Result.err(
            code: :archived_artifact_not_found,
            message: "No archived artifact '#{artifact_key}' for #{task_id}.",
            details: {
              task_id: task_id,
              artifact_key: artifact_key,
              available_keys: artifacts.map { |artifact| artifact[:key] }
            }
          )
        end
      end
    end
  end
end
