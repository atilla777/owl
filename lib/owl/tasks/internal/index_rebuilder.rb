# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative 'atomic_yaml_writer'
require_relative 'id_generator'
require_relative 'task_reader'
require_relative '../../result'

module Owl
  module Tasks
    module Internal
      module IndexRebuilder
        SCHEMA_VERSION = 1

        module_function

        def rebuild(tasks_root:, index_path:)
          dir = Pathname.new(tasks_root.to_s)
          entries = []
          errors = []

          task_dirs(dir).each do |task_dir|
            id = task_dir.basename.to_s
            entry, error = read_entry(task_dir: task_dir, task_id: id)
            entries << entry if entry
            errors << error if error
          end

          entries.sort_by! { |entry| IdGenerator.parse(entry['id']) || -1 }

          payload = { 'schema_version' => SCHEMA_VERSION, 'tasks' => entries }
          AtomicYamlWriter.write(path: index_path, payload: payload)

          Result.ok(index_path: index_path.to_s, tasks: entries, errors: errors)
        end

        def task_dirs(dir)
          return [] unless dir.directory?

          dir.children.select do |child|
            child.directory? && IdGenerator.parse(child.basename.to_s)
          end
        end

        def read_entry(task_dir:, task_id:)
          path = task_dir.join(TaskReader::TASK_FILENAME)
          return [nil, { task_id: task_id, code: :task_yaml_missing, path: path.to_s }] unless path.exist?

          raw = YAML.safe_load(path.read, aliases: false, permitted_classes: [Time])
          return [nil, { task_id: task_id, code: :task_yaml_invalid, path: path.to_s }] unless raw.is_a?(Hash)

          [build_index_entry(raw, task_id: task_id), nil]
        rescue Psych::SyntaxError => e
          [nil, { task_id: task_id, code: :task_yaml_invalid, path: path.to_s, message: e.message }]
        end

        def build_index_entry(raw, task_id:)
          workflow = raw['workflow']
          workflow_key = workflow.is_a?(Hash) ? workflow['key'] : workflow

          {
            'id' => raw['id'] || task_id,
            'title' => raw['title'],
            'workflow' => workflow_key,
            'kind' => raw['kind'],
            'parent_id' => raw['parent_id'],
            'priority' => raw['priority'],
            'created_at' => raw['created_at'],
            'status' => raw['status'],
            'archived_at' => raw['archived_at']
          }
        end
      end
    end
  end
end
