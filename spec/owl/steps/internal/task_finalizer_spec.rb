# frozen_string_literal: true

require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/steps/internal/task_finalizer'
require 'owl/tasks/internal/current_pointer'
require 'owl/tasks/internal/paths'

RSpec.describe Owl::Steps::Internal::TaskFinalizer do
  def cli(argv, root)
    Owl::Cli::Api.run(argv: argv, stdout: StringIO.new, stderr: StringIO.new, env: {}, cwd: root.to_s)
  end

  # Build a real project + task, then force task.yaml into the desired shape
  # (top-level status + per-step statuses). Returns the resolved paths bundle.
  def seed_task(root, status:, step_statuses:)
    cli(['init', '--root', root.to_s], root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        quick:
          enabled: true
          source: "workflows/quick/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/quick/workflow.yaml", <<~YAML)
      id: quick
      kind: task
      steps:
        - id: a
        - id: b
          requires: ["a"]
      artifacts: []
    YAML
    cli(['task', 'create', '--workflow', 'quick', '--title', 't', '--root', root.to_s, '--json'], root)

    path = "#{root}/tasks/TASK-0001/task.yaml"
    payload = YAML.safe_load_file(path)
    payload['status'] = status
    payload['steps'].each { |s| s['status'] = step_statuses.fetch(s['id']) }
    write(path, YAML.dump(payload))

    Owl::Tasks::Internal::Paths.resolve(root: root).value
  end

  def set_pointer(paths, task_id)
    Owl::Tasks::Internal::CurrentPointer.write(local_state_root: paths[:local_state], task_id: task_id)
  end

  def task_status(paths)
    YAML.safe_load_file("#{paths[:tasks]}/TASK-0001/task.yaml")['status']
  end

  def pointer_exists?(paths)
    Owl::Tasks::Internal::CurrentPointer.pointer_path(local_state_root: paths[:local_state]).exist?
  end

  describe '.call' do
    it 'promotes a non-terminal task to done and releases the pointer when all steps are terminal' do
      with_tmp_project do |root|
        paths = seed_task(root, status: 'open', step_statuses: { 'a' => 'done', 'b' => 'skipped' })
        set_pointer(paths, 'TASK-0001')

        result = described_class.call(
          root: root, tasks_root: paths[:tasks], local_state_root: paths[:local_state], task_id: 'TASK-0001'
        )

        expect(result).to be(true)
        expect(task_status(paths)).to eq('done')
        expect(pointer_exists?(paths)).to be(false)
      end
    end

    it 'releases the pointer but leaves an archived task archived (no overwrite to done)' do
      with_tmp_project do |root|
        paths = seed_task(root, status: 'archived', step_statuses: { 'a' => 'done', 'b' => 'done' })
        set_pointer(paths, 'TASK-0001')

        result = described_class.call(
          root: root, tasks_root: paths[:tasks], local_state_root: paths[:local_state], task_id: 'TASK-0001'
        )

        expect(result).to be(true)
        expect(task_status(paths)).to eq('archived')
        expect(pointer_exists?(paths)).to be(false)
      end
    end

    it 'is a no-op (false) when not all steps are terminal' do
      with_tmp_project do |root|
        paths = seed_task(root, status: 'open', step_statuses: { 'a' => 'done', 'b' => 'pending' })
        set_pointer(paths, 'TASK-0001')

        result = described_class.call(
          root: root, tasks_root: paths[:tasks], local_state_root: paths[:local_state], task_id: 'TASK-0001'
        )

        expect(result).to be(false)
        expect(task_status(paths)).to eq('open')
        expect(pointer_exists?(paths)).to be(true)
      end
    end

    it 'is a no-op (false) for an already-done task' do
      with_tmp_project do |root|
        paths = seed_task(root, status: 'done', step_statuses: { 'a' => 'done', 'b' => 'done' })

        result = described_class.call(
          root: root, tasks_root: paths[:tasks], local_state_root: paths[:local_state], task_id: 'TASK-0001'
        )

        expect(result).to be(false)
        expect(task_status(paths)).to eq('done')
      end
    end

    it 'is a no-op (false) for an abandoned task' do
      with_tmp_project do |root|
        paths = seed_task(root, status: 'abandoned', step_statuses: { 'a' => 'done', 'b' => 'skipped' })

        result = described_class.call(
          root: root, tasks_root: paths[:tasks], local_state_root: paths[:local_state], task_id: 'TASK-0001'
        )

        expect(result).to be(false)
        expect(task_status(paths)).to eq('abandoned')
      end
    end

    it 'does not touch the current pointer of a different task' do
      with_tmp_project do |root|
        paths = seed_task(root, status: 'open', step_statuses: { 'a' => 'done', 'b' => 'done' })
        set_pointer(paths, 'TASK-9999')

        result = described_class.call(
          root: root, tasks_root: paths[:tasks], local_state_root: paths[:local_state], task_id: 'TASK-0001'
        )

        expect(result).to be(true)
        expect(task_status(paths)).to eq('done')
        # The other task's pointer survives.
        expect(pointer_exists?(paths)).to be(true)
        pointer = Owl::Tasks::Internal::CurrentPointer.read(local_state_root: paths[:local_state])
        expect(pointer.value[:task_id]).to eq('TASK-9999')
      end
    end
  end
end
