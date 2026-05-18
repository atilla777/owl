# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/archive/api'
require 'owl/cli/api'
require 'owl/tasks/internal/archive/atomic_subtree_mover'
require 'owl/tasks/internal/archive/path_rename'
require 'owl/tasks/internal/atomic_yaml_writer'

RSpec.describe 'composite atomic archive' do
  def run_cli(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def default_workflow_yaml
    <<~YAML
      id: feature
      kind: task
      artifacts:
        spec:
          type: spec
          storage:
            role: tasks
            path: "{{task.id}}/spec.md"
      steps:
        - id: specify
          creates: [spec]
        - id: verify
          requires: [specify]
        - id: publish
          requires: [verify]
    YAML
  end

  def setup_project(root)
    run_cli(['init', '--root', root.to_s], cwd: root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", default_workflow_yaml)
  end

  def create_task(root:, title:, parent: nil)
    argv = ['task', 'create', '--workflow', 'feature', '--title', title,
            '--root', root.to_s, '--json']
    argv += ['--parent', parent] if parent
    _, stdout, = run_cli(argv, cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  def mark_composite(root, task_id)
    path = Pathname.new("#{root}/tasks/#{task_id}/task.yaml")
    payload = YAML.safe_load(path.read, aliases: false, permitted_classes: [Time])
    payload['kind'] = 'composite_task'
    Owl::Tasks::Internal::AtomicYamlWriter.write(path: path, payload: payload)
  end

  def force_step_status(root, task_id, step_id, status)
    path = Pathname.new("#{root}/tasks/#{task_id}/task.yaml")
    payload = YAML.safe_load(path.read, aliases: false, permitted_classes: [Time])
    payload['steps'].find { |s| s['id'] == step_id }['status'] = status
    Owl::Tasks::Internal::AtomicYamlWriter.write(path: path, payload: payload)
  end

  def mark_all_done(root, task_id, step_ids)
    step_ids.each { |id| force_step_status(root, task_id, id, 'done') }
  end

  def rebuild_index(root)
    run_cli(['task', 'index', 'rebuild', '--root', root.to_s, '--json'], cwd: root)
  end

  def fail_rename_on_nth_call(target_call_index)
    call_count = 0
    original_rename = Owl::Tasks::Internal::Archive::PathRename.method(:call)
    allow(Owl::Tasks::Internal::Archive::PathRename).to receive(:call).and_wrap_original do |_method, **kwargs|
      call_count += 1
      if call_count == target_call_index
        next Owl::Result.err(
          code: :rename_failed, message: 'simulated',
          details: { source: kwargs[:source].to_s, dest: kwargs[:dest].to_s,
                     error_class: 'Errno::EXDEV', reason: 'simulated' }
        )
      end

      original_rename.call(**kwargs)
    end
  end

  def task_yaml_bytes(root, ids)
    ids.to_h { |id| [id, Pathname.new("#{root}/tasks/#{id}/task.yaml").read] }
  end

  def expect_all_archived(root, ids, archived_at:)
    archive_root = Pathname.new("#{root}/tasks/archive")
    archived_dirs = archive_root.children.select(&:directory?).map { |c| c.basename.to_s }
    expect(archived_dirs.size).to eq(ids.size)
    expect_sources_moved_into_archive(root, ids, archived_dirs)
    expect_archived_task_yamls(archive_root, archived_dirs, archived_at)
  end

  def expect_sources_moved_into_archive(root, ids, archived_dirs)
    ids.each do |id|
      expect((Pathname.new(root) + 'tasks' + id).exist?).to be(false)
      expect(archived_dirs.any? { |name| name.include?(id) }).to be(true)
    end
  end

  def expect_archived_task_yamls(archive_root, archived_dirs, archived_at)
    archived_dirs.each do |name|
      payload = YAML.safe_load((archive_root + name + 'task.yaml').read,
                               aliases: false, permitted_classes: [Time])
      expect(payload['status']).to eq('archived')
      expect(payload['archived_at']).to eq(archived_at)
    end
  end

  def expect_sources_restored(root, ids, original_bytes)
    ids.each do |id|
      expect((Pathname.new(root) + 'tasks' + id).directory?).to be(true)
      expect(Pathname.new("#{root}/tasks/#{id}/task.yaml").read).to eq(original_bytes[id])
    end
    archive_dir = Pathname.new("#{root}/tasks/archive")
    expect(archive_dir.exist? && archive_dir.children.any?).to be(false)
  end

  def setup_composite_with_ready_children(root)
    parent_id = create_task(root: root, title: 'parent')
    mark_composite(root, parent_id)
    child_a = create_task(root: root, title: 'child a', parent: parent_id)
    child_b = create_task(root: root, title: 'child b', parent: parent_id)
    rebuild_index(root)
    mark_all_done(root, parent_id, %w[specify verify publish])
    mark_all_done(root, child_a, %w[specify verify publish])
    mark_all_done(root, child_b, %w[specify verify publish])
    [parent_id, child_a, child_b]
  end

  let(:now) { Time.utc(2026, 5, 18, 12, 0, 0) }

  describe 'happy path' do
    it 'atomically archives composite parent + all ready children' do
      with_tmp_project do |root|
        setup_project(root)
        parent_id, child_a, child_b = setup_composite_with_ready_children(root)
        ids = [parent_id, child_a, child_b]

        result = Owl::Archive::Api.archive_task(root: root, task_id: parent_id, now: now)
        index = YAML.safe_load(Pathname.new("#{root}/tasks/index.yaml").read)

        aggregate_failures do
          expect(result).to be_ok
          expect(result.value[:rolled_back]).to be(false)
          expect(result.value[:txn_id]).to match(/\A[0-9a-f]{16}\z/)
          expect(result.value[:archived]).to eq([child_a, child_b].sort + [parent_id])
          expect_all_archived(root, ids, archived_at: '2026-05-18T12:00:00Z')
          expect(index['tasks'].map { |t| t['id'] }).not_to include(*ids)
          staging = Pathname.new("#{root}/tasks/.archive-staging")
          expect(!staging.exist? || staging.children.empty?).to be(true)
        end
      end
    end
  end

  describe 'child readiness pre-flight' do
    it 'fails with :composite_with_unready_children when a child has incomplete steps' do
      with_tmp_project do |root|
        setup_project(root)
        parent_id = create_task(root: root, title: 'parent')
        mark_composite(root, parent_id)
        ready_child = create_task(root: root, title: 'ready', parent: parent_id)
        unready_child = create_task(root: root, title: 'unready', parent: parent_id)
        rebuild_index(root)
        mark_all_done(root, parent_id, %w[specify verify publish])
        mark_all_done(root, ready_child, %w[specify verify publish])
        force_step_status(root, unready_child, 'specify', 'done') # verify+publish stay pending

        result = Owl::Archive::Api.archive_task(root: root, task_id: parent_id, now: now)

        aggregate_failures do
          expect(result).to be_err
          expect(result.code).to eq(:composite_with_unready_children)
          unready = result.details[:unready_children]
          unready_ids = unready.map { |entry| entry[:id] }
          expect(unready_ids).to eq([unready_child])
          missing_step_ids = unready.first[:missing_steps].map { |s| s[:id] }
          expect(missing_step_ids).to include('verify', 'publish')

          # No file moves happened.
          [parent_id, ready_child, unready_child].each do |id|
            expect((Pathname.new(root) + 'tasks' + id).directory?).to be(true)
          end
          archive_dir = Pathname.new("#{root}/tasks/archive")
          expect(archive_dir.exist? && archive_dir.children.any?).to be(false)
        end
      end
    end
  end

  describe 'fault-injection rollback' do
    it 'rolls back fully when phase 1 (move-into-staging) returns :rename_failed midway' do
      with_tmp_project do |root|
        setup_project(root)
        parent_id, child_a, child_b = setup_composite_with_ready_children(root)
        ids = [parent_id, child_a, child_b]
        original_bytes = task_yaml_bytes(root, ids)
        fail_rename_on_nth_call(2)

        result = Owl::Archive::Api.archive_task(root: root, task_id: parent_id, now: now)

        aggregate_failures do
          expect(result).to be_err
          expect(result.code).to eq(:composite_archive_failed)
          expect(result.details[:rolled_back]).to be(true)
          expect(result.details[:failed_at]).to eq(:move_into_staging)
          expect(result.details[:txn_id]).to match(/\A[0-9a-f]{16}\z/)
          expect_sources_restored(root, ids, original_bytes)
        end
      end
    end

    it 'rolls back fully when phase 2 (commit) fails midway' do
      with_tmp_project do |root|
        setup_project(root)
        parent_id, child_a, child_b = setup_composite_with_ready_children(root)
        ids = [parent_id, child_a, child_b]
        original_bytes = task_yaml_bytes(root, ids)
        # 3 phase-1 renames succeed + 1 phase-2 OK; fail on call #5 (second phase-2 commit).
        fail_rename_on_nth_call(5)

        result = Owl::Archive::Api.archive_task(root: root, task_id: parent_id, now: now)

        aggregate_failures do
          expect(result).to be_err
          expect(result.code).to eq(:composite_archive_failed)
          expect(result.details[:rolled_back]).to be(true)
          expect(result.details[:failed_at]).to eq(:commit)
          expect_sources_restored(root, ids, original_bytes)
        end
      end
    end
  end

  describe 'current-pointer reset' do
    it 'clears current.yaml when archiving a composite parent that is the current task' do
      with_tmp_project do |root|
        setup_project(root)
        parent_id, _ca, _cb = setup_composite_with_ready_children(root)

        run_cli(['task', 'use', parent_id, '--root', root.to_s, '--json'], cwd: root)
        pointer_path = Pathname.new("#{root}/.owl/local/current.yaml")
        expect(pointer_path.exist?).to be(true)

        result = Owl::Archive::Api.archive_task(root: root, task_id: parent_id, now: now)

        expect(result).to be_ok
        expect(result.value[:current_reset]).to include(parent_id)
        expect(pointer_path.exist?).to be(false)
      end
    end
  end
end
