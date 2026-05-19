# frozen_string_literal: true

require 'pathname'
require 'yaml'

require_relative '../result'
require_relative 'backend'
require_relative 'backends/filesystem'

module Owl
  module Tasks
    module Api
      module_function

      def create(root:, workflow:, title:, parent_id: nil, kind: nil)
        resolve_backend(root: root).create(
          workflow: workflow,
          title: title,
          parent_id: parent_id,
          kind: kind
        )
      end

      def list(root:)
        resolve_backend(root: root).list
      end

      def inspect(root:, task_id:)
        resolve_backend(root: root).inspect_task(task_id: task_id)
      end

      def use(root:, task_id:)
        resolve_backend(root: root).use(task_id: task_id)
      end

      def current(root:)
        resolve_backend(root: root).current
      end

      def rebuild_index(root:)
        resolve_backend(root: root).rebuild_index
      end

      def children(root:, parent_id:)
        resolve_backend(root: root).children(parent_id: parent_id)
      end

      def parent(root:, task_id:)
        resolve_backend(root: root).parent(task_id: task_id)
      end

      def tree(root:)
        resolve_backend(root: root).tree
      end

      def aggregate_status(root:, task_id:)
        resolve_backend(root: root).aggregate_status(task_id: task_id)
      end

      def child_create(root:, parent_id:, workflow:, title:, brief_body: nil)
        resolve_backend(root: root).child_create(
          parent_id: parent_id,
          workflow: workflow,
          title: title,
          brief_body: brief_body
        )
      end

      def split(root:, task_id:, kind: 'composite_task')
        resolve_backend(root: root).split(task_id: task_id, kind: kind)
      end

      def archive(root:, task_id:, now: Time.now.utc)
        resolve_backend(root: root).archive_task(task_id: task_id, now: now)
      end

      def resolve_backend(root:)
        backend_name = read_backend_name(root: root)
        case backend_name
        when nil, 'filesystem'
          Backends::Filesystem.new(root: root)
        else
          raise UnknownBackendError, "Unknown Owl tasks backend: #{backend_name.inspect}"
        end
      end

      def read_backend_name(root:)
        config_path = Pathname.new(root.to_s) + '.owl/config.yaml'
        return nil unless config_path.exist?

        raw = YAML.safe_load(config_path.read, aliases: false)
        return nil unless raw.is_a?(Hash)

        settings = raw['settings']
        return nil unless settings.is_a?(Hash)

        storage = settings['storage']
        return nil unless storage.is_a?(Hash)

        backend = storage['backend']
        backend.is_a?(String) && !backend.empty? ? backend : nil
      rescue Psych::SyntaxError
        nil
      end
    end
  end
end
