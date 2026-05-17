# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/archive/api'
require 'owl/cli/api'
require 'owl/tasks/internal/atomic_yaml_writer'

RSpec.describe Owl::Archive::Api do
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

  def setup_project(root, workflow_yaml: nil, title: 'My Task')
    run_cli(['init', '--root', root.to_s], cwd: root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", workflow_yaml || default_workflow_yaml)

    _, stdout, = run_cli(['task', 'create', '--workflow', 'feature', '--title', title,
                          '--root', root.to_s, '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  def force_step_status(root, task_id, step_id, status)
    task_path = Pathname.new(root) + 'tasks' + task_id + 'task.yaml'
    payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
    payload['steps'].find { |s| s['id'] == step_id }['status'] = status
    Owl::Tasks::Internal::AtomicYamlWriter.write(path: task_path, payload: payload)
  end

  def mark_all_done(root, task_id, step_ids)
    step_ids.each { |id| force_step_status(root, task_id, id, 'done') }
  end

  describe '.archive_task' do
    let(:now) { Time.utc(2026, 5, 17, 12, 0, 0) }

    it 'archives a fully completed feature task into tasks/archive/<date>-<id>-<slug>' do
      with_tmp_project do |root|
        task_id = setup_project(root, title: 'Feature Foo')
        mark_all_done(root, task_id, %w[specify verify publish])

        result = described_class.archive_task(root: root, task_id: task_id, now: now)
        dest = Pathname.new("#{root}/tasks/archive/2026-05-17-#{task_id}-feature-foo")
        archived = YAML.safe_load((dest + 'task.yaml').read, aliases: false, permitted_classes: [Time])
        index = YAML.safe_load(Pathname.new("#{root}/tasks/index.yaml").read)

        aggregate_failures do
          expect(result).to be_ok
          expect(dest.directory?).to be(true)
          expect((Pathname.new(root) + 'tasks' + task_id).exist?).to be(false)
          expect(archived).to include('status' => 'archived', 'archived_at' => '2026-05-17T12:00:00Z')
          expect(result.value).to include(
            to: dest.to_s, slug: 'feature-foo', collision_suffix: nil,
            archived_at: '2026-05-17T12:00:00Z', current_reset: false
          )
          expect(index['tasks'].map { |t| t['id'] }).not_to include(task_id)
        end
      end
    end

    it 'accepts a skipped publish step as opt-out' do
      with_tmp_project do |root|
        task_id = setup_project(root, title: 'Skipped publish')
        force_step_status(root, task_id, 'specify', 'done')
        force_step_status(root, task_id, 'verify', 'done')
        force_step_status(root, task_id, 'publish', 'skipped')

        result = described_class.archive_task(root: root, task_id: task_id, now: now)
        expect(result).to be_ok
      end
    end

    it 'reports workflow_incomplete with incomplete_steps in graph order' do
      with_tmp_project do |root|
        task_id = setup_project(root, title: 't')
        force_step_status(root, task_id, 'specify', 'done')

        result = described_class.archive_task(root: root, task_id: task_id, now: now)
        expect(result).to be_err
        expect(result.code).to eq(:workflow_incomplete)
        ids = result.details[:incomplete_steps].map { |s| s[:id] }
        expect(ids).to eq(%w[verify publish])
      end
    end

    it 'reports publish_required when only publish remains pending' do
      with_tmp_project do |root|
        task_id = setup_project(root, title: 't')
        force_step_status(root, task_id, 'specify', 'done')
        force_step_status(root, task_id, 'verify', 'done')

        result = described_class.archive_task(root: root, task_id: task_id, now: now)
        expect(result).to be_err
        expect(result.code).to eq(:publish_required)
      end
    end

    it 'archives workflows without a publish step when all steps are done' do
      workflow_yaml = <<~YAML
        id: feature
        kind: task
        steps:
          - id: specify
          - id: verify
            requires: [specify]
      YAML
      with_tmp_project do |root|
        task_id = setup_project(root, workflow_yaml: workflow_yaml, title: 'No Publish')
        mark_all_done(root, task_id, %w[specify verify])

        result = described_class.archive_task(root: root, task_id: task_id, now: now)
        expect(result).to be_ok
      end
    end

    it 'is idempotent: an already-archived task returns already_archived' do
      with_tmp_project do |root|
        task_id = setup_project(root, title: 'Idem')
        # Pre-write the task with status: archived without moving it. Simulates a manual marker
        # or a previous archive whose directory move was reverted.
        task_path = Pathname.new("#{root}/tasks/#{task_id}/task.yaml")
        payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
        payload['status'] = 'archived'
        payload['archived_at'] = '2026-05-17T10:00:00Z'
        Owl::Tasks::Internal::AtomicYamlWriter.write(path: task_path, payload: payload)

        result = described_class.archive_task(root: root, task_id: task_id, now: now)
        expect(result).to be_err
        expect(result.code).to eq(:already_archived)
        expect(result.details[:archived_at]).to eq('2026-05-17T10:00:00Z')
      end
    end

    it 'returns task_not_found for an unknown task id' do
      with_tmp_project do |root|
        setup_project(root, title: 't')
        result = described_class.archive_task(root: root, task_id: 'TASK-9999', now: now)
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end

    it 'appends -2 / -3 suffix on slug collisions' do
      with_tmp_project do |root|
        task_id = setup_project(root, title: 't')
        mark_all_done(root, task_id, %w[specify verify publish])

        FileUtils.mkdir_p("#{root}/tasks/archive/2026-05-17-#{task_id}-t")
        FileUtils.mkdir_p("#{root}/tasks/archive/2026-05-17-#{task_id}-t-2")

        result = described_class.archive_task(root: root, task_id: task_id, now: now)
        expect(result).to be_ok
        expect(result.value[:collision_suffix]).to eq(3)
        expect(result.value[:to]).to end_with("2026-05-17-#{task_id}-t-3")
      end
    end

    it 'resets .owl/local/current.yaml when archiving the current task' do
      with_tmp_project do |root|
        task_id = setup_project(root, title: 'Current Task')
        mark_all_done(root, task_id, %w[specify verify publish])

        run_cli(['task', 'use', task_id, '--root', root.to_s, '--json'], cwd: root)
        pointer_path = Pathname.new("#{root}/.owl/local/current.yaml")
        expect(pointer_path.exist?).to be(true)

        result = described_class.archive_task(root: root, task_id: task_id, now: now)
        expect(result).to be_ok
        expect(result.value[:current_reset]).to be(true)
        expect(pointer_path.exist?).to be(false)
      end
    end

    it 'leaves .owl/local/current.yaml alone when archiving a different task' do
      with_tmp_project do |root|
        task_id_a = setup_project(root, title: 'a')
        # Create a second task.
        _, stdout, = run_cli(['task', 'create', '--workflow', 'feature', '--title', 'b',
                              '--root', root.to_s, '--json'], cwd: root)
        task_id_b = JSON.parse(stdout).dig('task', 'id')

        mark_all_done(root, task_id_a, %w[specify verify publish])
        run_cli(['task', 'use', task_id_b, '--root', root.to_s, '--json'], cwd: root)

        result = described_class.archive_task(root: root, task_id: task_id_a, now: now)
        expect(result).to be_ok
        expect(result.value[:current_reset]).to be(false)

        pointer = YAML.safe_load(Pathname.new("#{root}/.owl/local/current.yaml").read)
        expect(pointer['task_id']).to eq(task_id_b)
      end
    end

    it 'refuses composite_task archive when there are non-archived children' do
      with_tmp_project do |root|
        parent_id = setup_project(root, title: 'parent')
        # Mark parent as composite_task in task.yaml.
        parent_path = Pathname.new("#{root}/tasks/#{parent_id}/task.yaml")
        parent_payload = YAML.safe_load(parent_path.read, aliases: false, permitted_classes: [Time])
        parent_payload['kind'] = 'composite_task'
        Owl::Tasks::Internal::AtomicYamlWriter.write(path: parent_path, payload: parent_payload)

        # Create a child task with parent_id pointing at parent.
        _, stdout, = run_cli(['task', 'create', '--workflow', 'feature', '--title', 'child',
                              '--parent', parent_id, '--root', root.to_s, '--json'], cwd: root)
        child_id = JSON.parse(stdout).dig('task', 'id')

        # Rebuild the index to surface parent_id + (nil) status.
        run_cli(['task', 'index', 'rebuild', '--root', root.to_s, '--json'], cwd: root)

        mark_all_done(root, parent_id, %w[specify verify publish])

        result = described_class.archive_task(root: root, task_id: parent_id, now: now)
        expect(result).to be_err
        expect(result.code).to eq(:composite_with_open_children)
        expect(result.details[:open_children]).to include(child_id)
      end
    end

    it 'restores task.yaml when the directory rename fails (atomicity)' do
      with_tmp_project do |root|
        task_id = setup_project(root, title: 't')
        mark_all_done(root, task_id, %w[specify verify publish])

        task_path = Pathname.new("#{root}/tasks/#{task_id}/task.yaml")
        original_bytes = task_path.read

        allow_any_instance_of(Pathname).to receive(:rename).and_wrap_original do |original, *args|
          # Only intercept the directory rename; allow atomic-writer renames (those go via File.rename).
          raise Errno::EXDEV, 'cross-device move' if original.receiver.to_s.end_with?(task_id)

          original.call(*args)
        end

        result = described_class.archive_task(root: root, task_id: task_id, now: now)
        expect(result).to be_err
        expect(result.code).to eq(:archive_move_failed)

        # task.yaml bytes are restored.
        expect(task_path.read).to eq(original_bytes)
        # destination does not exist.
        archive_dir = Pathname.new("#{root}/tasks/archive")
        expect(archive_dir.children.any? { |c| c.basename.to_s.include?(task_id) }).to be(false)
      end
    end
  end
end
