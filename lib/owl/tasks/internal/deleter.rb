# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'yaml'

require_relative '../../result'
require_relative 'archive/claim_resetter'
require_relative 'archive/current_resetter'
require_relative 'atomic_yaml_writer'
require_relative 'id_generator'
require_relative 'index_writer'
require_relative 'paths'
require_relative 'task_mutation_lock'
require_relative 'task_reader'

module Owl
  module Tasks
    module Internal
      module Deleter
        module_function

        def call(root:, task_id:, recursive: false, locks: Owl::Locks::Api, clock: Time,
                 sleeper: ->(seconds) { sleep(seconds) })
          paths_result = Paths.resolve(root: root)
          return paths_result if paths_result.err?

          tasks_root = paths_result.value[:tasks]
          task_id = task_id.to_s
          task_dir = Pathname.new(tasks_root.to_s) / task_id
          unless task_dir.directory?
            return Result.err(
              code: :task_not_found,
              message: "Task '#{task_id}' not found under #{tasks_root}.",
              details: { task_id: task_id }
            )
          end

          descendants = collect_descendants(tasks_root: tasks_root, root_id: task_id)
          guard = guard_children(task_id: task_id, tasks_root: tasks_root, descendants: descendants,
                                 recursive: recursive)
          return guard if guard

          ids_to_delete = recursive ? (descendants + [task_id]) : [task_id]
          remove_all(root: root, tasks_root: tasks_root, ids: ids_to_delete, locks: locks, clock: clock,
                     sleeper: sleeper, paths: paths_result.value, task_dir: task_dir)
        end

        # Refuse to silently orphan children. Deleting a composite parent whose
        # subtree still exists without `--recursive` would leave every child
        # pointing at a now-missing `parent_id` — invisible in `task tree` under
        # its old parent and only surfaced by `owl doctor`. Return the direct
        # child list so the caller can decide to re-parent or pass `--recursive`.
        def guard_children(task_id:, tasks_root:, descendants:, recursive:)
          return nil if recursive || descendants.empty?

          direct = direct_children(tasks_root: tasks_root, parent_id: task_id)
          Result.err(
            code: :task_has_children,
            message: "Task '#{task_id}' has #{descendants.size} descendant task(s); " \
                     'pass --recursive to delete the whole subtree.',
            details: { task_id: task_id, children: direct, descendants: descendants }
          )
        end

        def remove_all(root:, tasks_root:, ids:, locks:, clock:, sleeper:, paths:, task_dir:)
          ids.each do |id|
            dir = Pathname.new(tasks_root.to_s) / id
            next unless dir.directory?

            removed = remove_dir_locked(root: root, task_id: id, task_dir: dir, locks: locks, clock: clock,
                                        sleeper: sleeper)
            return removed if removed.err?
          end

          clean_dangling_refs(root: root, tasks_root: tasks_root, deleted_ids: ids)

          rebuild = IndexWriter.rebuild(root: root, tasks_root: tasks_root, index_path: paths[:index])
          return rebuild if rebuild.err?

          reset_local_state(local_state_root: paths[:local_state], ids: ids)

          Result.ok(
            task_id: ids.last.to_s,
            removed: true,
            deleted_path: task_dir.to_s,
            removed_task_ids: ids
          )
        end

        # Drop claim leases + the current-task pointer for every deleted id, so
        # `owl task current` reports "no current task" rather than chasing a
        # now-missing directory (`task_not_found`). Deleting a non-current task
        # leaves the pointer untouched.
        def reset_local_state(local_state_root:, ids:)
          ids.each do |id|
            Archive::ClaimResetter.delete_if_present(local_state_root: local_state_root, task_id: id)
            Archive::CurrentResetter.reset_if_matches(local_state_root: local_state_root, task_id: id)
          end
        end

        # Direct children of `parent_id`, read from the authoritative task.yaml
        # files (not the index, which may be drifted).
        def direct_children(tasks_root:, parent_id:)
          parent_map(tasks_root).select { |_child, parent| parent == parent_id }.keys.sort
        end

        # All transitive descendants of `root_id`, leaves-first, with a cycle
        # guard so a corrupt parent_id loop cannot spin forever.
        def collect_descendants(tasks_root:, root_id:)
          map = parent_map(tasks_root)
          ordered = []
          seen = { root_id => true }
          frontier = [root_id]
          until frontier.empty?
            current = frontier.shift
            kids = map.select { |_child, parent| parent == current }.keys.sort
            kids.each do |kid|
              next if seen[kid]

              seen[kid] = true
              ordered << kid
              frontier << kid
            end
          end
          ordered.reverse
        end

        # child_id => parent_id map across every task dir under `tasks_root`.
        def parent_map(tasks_root)
          dir = Pathname.new(tasks_root.to_s)
          return {} unless dir.directory?

          dir.children.each_with_object({}) do |child, acc|
            next unless child.directory? && IdGenerator.parse(child.basename.to_s)

            yaml = child.join(TaskReader::TASK_FILENAME)
            next unless yaml.file?

            raw = YAML.safe_load(yaml.read, aliases: false, permitted_classes: [Time])
            acc[child.basename.to_s] = raw['parent_id'].to_s if raw.is_a?(Hash)
          rescue Psych::SyntaxError
            next
          end
        end

        # Hold the deleted task's own mutation lock for the rm_rf only, so a
        # concurrent writer of the SAME task cannot have its task.yaml removed
        # mid-write. The caller runs `clean_dangling_refs` (which locks each
        # OTHER task in turn) and the index rebuild AFTER this returns, outside
        # this lock, so two parallel deletes can never nest `lock(deleted) ->
        # lock(child)` into a lock-ordering deadlock.
        def remove_dir_locked(root:, task_id:, task_dir:, locks:, clock:, sleeper:)
          TaskMutationLock.with_lock(
            root: root, task_id: task_id.to_s, locks: locks, clock: clock, sleeper: sleeper
          ) do
            FileUtils.rm_rf(task_dir.to_s)
            Result.ok(:removed)
          end
        end

        # Strip every deleted id from all surviving tasks' `blocked_by` so no
        # dangling dependency edge survives the delete (preferred over leaving
        # references that downstream readers must defensively ignore). Runs
        # before the index rebuild so the refreshed index reflects the cleanup.
        def clean_dangling_refs(root:, tasks_root:, deleted_ids:)
          dir = Pathname.new(tasks_root.to_s)
          return unless dir.directory?

          deleted = Array(deleted_ids).map(&:to_s)
          dir.children.each do |child|
            next unless child.directory? && IdGenerator.parse(child.basename.to_s)

            # Each affected task is scrubbed under ITS OWN per-task mutation lock,
            # one at a time (never holding two), so a concurrent edit of that task
            # from another session cannot lose the dependency cleanup.
            TaskMutationLock.with_lock(root: root, task_id: child.basename.to_s) do
              scrub_task_blocked_by(child.join(TaskReader::TASK_FILENAME), deleted)
            end
          end
        end

        def scrub_task_blocked_by(task_yaml, deleted_ids)
          return unless task_yaml.file?

          raw = YAML.safe_load(task_yaml.read, aliases: false, permitted_classes: [Time])
          return unless raw.is_a?(Hash)

          blocked_by = Array(raw['blocked_by'])
          remaining = blocked_by - deleted_ids
          return if remaining == blocked_by

          raw['blocked_by'] = remaining
          AtomicYamlWriter.write(path: task_yaml, payload: raw)
        rescue Psych::SyntaxError
          nil
        end
      end
    end
  end
end
