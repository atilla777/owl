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

  describe 'read-only archive surface' do
    let(:now) { Time.utc(2026, 5, 17, 12, 0, 0) }

    def archive_a_task(root, title:)
      task_id = setup_project(root, title: title)
      write("#{root}/tasks/#{task_id}/spec.md", "# spec for #{title}\n")
      mark_all_done(root, task_id, %w[specify verify publish])
      described_class.archive_task(root: root, task_id: task_id, now: now)
      task_id
    end

    describe '.list' do
      it 'returns an empty list when nothing is archived' do
        with_tmp_project do |root|
          setup_project(root, title: 't')
          result = described_class.list(root: root)
          expect(result).to be_ok
          expect(result.value[:archived]).to eq([])
        end
      end

      it 'enumerates archived tasks with id, slug, date, title and an existing path' do
        with_tmp_project do |root|
          task_id = archive_a_task(root, title: 'Feature Foo')
          result = described_class.list(root: root)

          aggregate_failures do
            expect(result).to be_ok
            entry = result.value[:archived].first
            expect(entry[:task_id]).to eq(task_id)
            expect(entry[:slug]).to eq('feature-foo')
            expect(entry[:archived_date]).to eq('2026-05-17')
            expect(entry[:title]).to eq('Feature Foo')
            expect(Pathname.new(entry[:path]).directory?).to be(true)
          end
        end
      end

      it 'propagates the config-load error when the project root is invalid' do
        with_tmp_project do |root|
          result = described_class.list(root: "#{root}/does-not-exist")
          expect(result).to be_err
        end
      end
    end

    describe '.show' do
      it 'returns the archived payload and artifact inventory' do
        with_tmp_project do |root|
          task_id = archive_a_task(root, title: 'Show Me')
          result = described_class.show(root: root, task_id: task_id)

          aggregate_failures do
            expect(result).to be_ok
            expect(result.value[:task_id]).to eq(task_id)
            expect(result.value[:title]).to eq('Show Me')
            expect(result.value[:workflow_key]).to eq('feature')
            expect(result.value[:status]).to eq('archived')
            expect(result.value[:steps].map { |s| s[:id] }).to eq(%w[specify verify publish])
            expect(result.value[:artifacts].map { |a| a[:key] }).to include('spec')
            expect(Pathname.new(result.value[:path]).directory?).to be(true)
          end
        end
      end

      it 'returns archived_task_not_found with available_ids for an unknown id' do
        with_tmp_project do |root|
          archive_a_task(root, title: 'Known')
          result = described_class.show(root: root, task_id: 'TASK-9999')

          aggregate_failures do
            expect(result).to be_err
            expect(result.code).to eq(:archived_task_not_found)
            expect(result.details[:available_ids]).to eq(['TASK-0001'])
          end
        end
      end
    end

    describe '.read' do
      it 'returns the artifact body for an existing key' do
        with_tmp_project do |root|
          task_id = archive_a_task(root, title: 'Read Me')
          result = described_class.read(root: root, task_id: task_id, artifact_key: 'spec')

          aggregate_failures do
            expect(result).to be_ok
            expect(result.value[:task_id]).to eq(task_id)
            expect(result.value[:artifact_key]).to eq('spec')
            expect(Pathname.new(result.value[:path]).file?).to be(true)
            expect(result.value[:body]).to be_a(String)
          end
        end
      end

      it 'returns archived_artifact_not_found with available_keys for a missing key' do
        with_tmp_project do |root|
          task_id = archive_a_task(root, title: 'Read Me')
          result = described_class.read(root: root, task_id: task_id, artifact_key: 'nope')

          aggregate_failures do
            expect(result).to be_err
            expect(result.code).to eq(:archived_artifact_not_found)
            expect(result.details[:available_keys]).to include('spec')
          end
        end
      end

      it 'returns archived_task_not_found for reading an unknown task id' do
        with_tmp_project do |root|
          setup_project(root, title: 't')
          result = described_class.read(root: root, task_id: 'TASK-9999', artifact_key: 'spec')
          expect(result).to be_err
          expect(result.code).to eq(:archived_task_not_found)
        end
      end
    end
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

    # End-to-end reproduction of the reported deadlock: a feature-style
    # workflow whose `archive` step runs `owl archive`, followed by a
    # `commit_push` step. At archive time the `archive` step is `running`
    # and `commit_push` is `pending`; the archive side effect must still run.
    def feature_with_archive_yaml
      <<~YAML
        id: feature
        kind: task
        steps:
          - id: implement
          - id: review_code
            requires: [implement]
          - id: merge_docs
            requires: [review_code]
          - id: archive
            requires: [merge_docs]
          - id: commit_push
            requires: [archive]
      YAML
    end

    it 'archives while the archive step is running and commit_push is pending' do
      with_tmp_project do |root|
        task_id = setup_project(root, workflow_yaml: feature_with_archive_yaml, title: 'Archive Me')
        mark_all_done(root, task_id, %w[implement review_code merge_docs])
        force_step_status(root, task_id, 'archive', 'running')
        # commit_push stays pending

        result = described_class.archive_task(root: root, task_id: task_id, now: now)
        dest = Pathname.new("#{root}/tasks/archive/2026-05-17-#{task_id}-archive-me")

        aggregate_failures do
          expect(result).to be_ok
          expect(dest.directory?).to be(true)
          expect((Pathname.new(root) + 'tasks' + task_id).exist?).to be(false)
        end
      end
    end

    it 'drives the full archive -> commit_push flow end-to-end via the CLI' do
      # The exact reported sequence: after the archive side effect moves the
      # task out of tasks/<id>/, the workflow must still complete `archive` and
      # `commit_push` against the archived location, and only THEN release the
      # current pointer.
      with_tmp_project do |root|
        task_id = setup_project(root, workflow_yaml: feature_with_archive_yaml, title: 'E2E')
        mark_all_done(root, task_id, %w[implement review_code])
        run_cli(['task', 'use', task_id, '--root', root.to_s, '--json'], cwd: root)
        pointer_path = Pathname.new("#{root}/.owl/local/current.yaml")
        live_dir = Pathname.new("#{root}/tasks/#{task_id}")
        archived_dir = Pathname.new("#{root}/tasks/archive/2026-05-17-#{task_id}-e2e")

        run_cli(['step', 'start', task_id, 'merge_docs', '--root', root.to_s, '--json'], cwd: root)
        run_cli(['step', 'complete', task_id, 'merge_docs', '--root', root.to_s, '--json'], cwd: root)
        run_cli(['step', 'start', task_id, 'archive', '--root', root.to_s, '--json'], cwd: root)

        # Archive side effect: directory moves, pointer is preserved.
        archive_result = described_class.archive_task(root: root, task_id: task_id, now: now)

        # status resolves the archived task mid-flow (was task_not_found before).
        status_code, status_out, = run_cli(['status', task_id, '--root', root.to_s, '--json'], cwd: root)

        # Completing `archive` resolves the moved task (was unknown_step_id before)
        # and does NOT release the pointer while commit_push is still pending.
        complete_archive, = run_cli(['step', 'complete', task_id, 'archive', '--root', root.to_s, '--json'], cwd: root)
        pointer_after_archive_step = pointer_path.exist?

        # Post-archive step runs and completes; the final completion releases the pointer.
        start_push, = run_cli(['step', 'start', task_id, 'commit_push', '--root', root.to_s, '--json'], cwd: root)
        complete_push, = run_cli(['step', 'complete', task_id, 'commit_push', '--root', root.to_s, '--json'], cwd: root)

        aggregate_failures do
          expect(archive_result).to be_ok
          expect(live_dir.exist?).to be(false)
          expect(archived_dir.directory?).to be(true)
          expect(pointer_path.exist?).to be(false) # released only after the final step
          expect(status_code).to eq(0)
          expect(JSON.parse(status_out).dig('task', 'id')).to eq(task_id)
          expect(complete_archive).to eq(0)
          expect(pointer_after_archive_step).to be(true)
          expect(start_push).to eq(0)
          expect(complete_push).to eq(0)
        end
      end
    end

    it 'still blocks archival when a pre-archive step is not done' do
      with_tmp_project do |root|
        task_id = setup_project(root, workflow_yaml: feature_with_archive_yaml, title: 't')
        mark_all_done(root, task_id, %w[implement review_code])
        force_step_status(root, task_id, 'merge_docs', 'running')
        force_step_status(root, task_id, 'archive', 'running')

        result = described_class.archive_task(root: root, task_id: task_id, now: now)
        expect(result).to be_err
        expect(result.code).to eq(:workflow_incomplete)
        ids = result.details[:incomplete_steps].map { |s| s[:id] }
        expect(ids).to eq(%w[merge_docs])
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

    it 'keeps .owl/local/current.yaml pointing at the archived task (reset is deferred)' do
      # Option-1 semantics: archival no longer clears the current pointer, so the
      # workflow can still drive its post-archive steps (e.g. commit_push). The
      # pointer is released later, when the final step completes.
      with_tmp_project do |root|
        task_id = setup_project(root, title: 'Current Task')
        mark_all_done(root, task_id, %w[specify verify publish])

        run_cli(['task', 'use', task_id, '--root', root.to_s, '--json'], cwd: root)
        pointer_path = Pathname.new("#{root}/.owl/local/current.yaml")
        expect(pointer_path.exist?).to be(true)

        result = described_class.archive_task(root: root, task_id: task_id, now: now)
        expect(result).to be_ok
        expect(result.value[:current_reset]).to be(false)
        expect(pointer_path.exist?).to be(true)
        expect(YAML.safe_load(pointer_path.read)['task_id']).to eq(task_id)
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

    it 'archives a composite_task independently of its children (leaves them in active tasks/)' do
      with_tmp_project do |root|
        parent_id = setup_project(root, title: 'parent')
        # Mark parent as composite_task in task.yaml.
        parent_path = Pathname.new("#{root}/tasks/#{parent_id}/task.yaml")
        parent_payload = YAML.safe_load(parent_path.read, aliases: false, permitted_classes: [Time])
        parent_payload['kind'] = 'composite_task'
        Owl::Tasks::Internal::AtomicYamlWriter.write(path: parent_path, payload: parent_payload)

        # Create a child task with parent_id pointing at parent (steps left pending).
        _, stdout, = run_cli(['task', 'create', '--workflow', 'feature', '--title', 'child',
                              '--parent', parent_id, '--root', root.to_s, '--json'], cwd: root)
        child_id = JSON.parse(stdout).dig('task', 'id')

        run_cli(['task', 'index', 'rebuild', '--root', root.to_s, '--json'], cwd: root)

        mark_all_done(root, parent_id, %w[specify verify publish])

        result = described_class.archive_task(root: root, task_id: parent_id, now: now)
        expect(result).to be_ok

        # Parent dir moved to archive, child dir stays active.
        expect((Pathname.new(root) + 'tasks' + parent_id).exist?).to be(false)
        expect((Pathname.new(root) + 'tasks' + child_id).directory?).to be(true)
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
