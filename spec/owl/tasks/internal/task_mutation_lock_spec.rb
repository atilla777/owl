# frozen_string_literal: true

require 'stringio'

require 'owl/tasks/api'
require 'owl/tasks/internal/task_mutation_lock'
require 'owl/tasks/internal/task_reader'
require 'owl/tasks/internal/atomic_yaml_writer'
require 'owl/tasks/internal/paths'
require 'owl/locks/api'
require 'owl/cli/internal/commands/init'

# Coverage for TASK-0035: every read-modify-write of a single `tasks/<id>/task.yaml`
# must be serialized under the repo-scoped `Owl::Locks` lock named "task-<id>" so a
# concurrent tracker/step mutation of the SAME task cannot lose an update, while
# mutations of DIFFERENT tasks still run in parallel.
RSpec.describe Owl::Tasks::Internal::TaskMutationLock do
  def init_project(root)
    Owl::Cli::Internal::Commands::Init.run(
      argv: ['--root', root.to_s], stdout: StringIO.new, stderr: StringIO.new, cwd: root.to_s, env: {}
    )
  end

  def seed(root)
    init_project(root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: feature
      steps:
        - id: a
      artifacts: []
    YAML
  end

  def lock_file(root, task_id)
    Pathname.new("#{root}/.owl/local/task-#{task_id}.lock")
  end

  describe '.lock_name' do
    it 'prefixes the task id with "task-" and is distinct per task' do
      expect(described_class.lock_name('TASK-0001')).to eq('task-TASK-0001')
      expect(described_class.lock_name('TASK-0001')).not_to eq(described_class.lock_name('TASK-0002'))
    end
  end

  describe '.with_lock' do
    it 'runs the block, returns its value and releases the lock' do
      with_tmp_project do |root|
        seed(root)
        result = described_class.with_lock(root: root, task_id: 'TASK-0001') { :done }

        expect(result).to eq(:done)
        expect(lock_file(root, 'TASK-0001')).not_to exist
      end
    end

    it 'releases the lock even when the block raises' do
      with_tmp_project do |root|
        seed(root)

        expect do
          described_class.with_lock(root: root, task_id: 'TASK-0001') { raise 'boom' }
        end.to raise_error(RuntimeError, 'boom')
        expect(lock_file(root, 'TASK-0001')).not_to exist
      end
    end

    it 'returns the lock error without running the block when acquisition fails' do
      with_tmp_project do |root|
        seed(root)
        # Foreign holder never releases and the clock is already past the deadline,
        # so the single retry exits with the recoverable lock_held error and the
        # block is never reached.
        Owl::Locks::Api.acquire(root: root, name: 'task-TASK-0001', token: 'foreign')
        now = Time.utc(2026, 1, 1, 12, 0, 0)
        clock = class_double(Time)
        allow(clock).to receive(:now)
          .and_return(now, now + described_class::ACQUIRE_TIMEOUT_SECONDS + 1)
        ran = false

        result = described_class.with_lock(
          root: root, task_id: 'TASK-0001', clock: clock, sleeper: ->(_s) {}
        ) { ran = true }

        expect(ran).to be(false)
        expect(result).to be_err
        expect(result.code).to eq(:lock_held)
      end
    end

    it 'does not block a different task (distinct lock names)' do
      with_tmp_project do |root|
        seed(root)
        Owl::Locks::Api.acquire(root: root, name: 'task-TASK-0001', token: 'foreign')

        # TASK-0001 is held by a foreign session, but TASK-0002 uses a different
        # lock name and proceeds immediately.
        result = described_class.with_lock(root: root, task_id: 'TASK-0002', sleeper: ->(_s) {}) { :ran }

        expect(result).to eq(:ran)
        expect(lock_file(root, 'TASK-0002')).not_to exist
      end
    end
  end

  describe 'serialization (no lost update on stale read)' do
    it 'waits out a foreign holder and reads the FRESH payload before writing' do
      with_tmp_project do |root|
        seed(root)
        Owl::Tasks::Api.create(root: root, workflow: 'feature', title: 't')
        tasks_root = Owl::Tasks::Internal::Paths.resolve(root: root).value[:tasks]

        # A foreign session holds the lock and, while our mutator is retrying,
        # commits its own edit (labels: ['foreign']) and then releases.
        foreign = Owl::Locks::Api.acquire(root: root, name: 'task-TASK-0001', token: 'foreign')
        now = Time.utc(2026, 1, 1, 12, 0, 0)
        clock = class_double(Time)
        allow(clock).to receive(:now).and_return(now)
        sleeper = lambda do |_s|
          read = Owl::Tasks::Internal::TaskReader.read(tasks_root: tasks_root, task_id: 'TASK-0001')
          payload = read.value[:payload]
          payload['labels'] = ['foreign']
          Owl::Tasks::Internal::AtomicYamlWriter.write(path: read.value[:path], payload: payload)
          Owl::Locks::Api.release(root: root, name: 'task-TASK-0001', token: foreign.value[:token])
        end

        described_class.with_lock(root: root, task_id: 'TASK-0001', clock: clock, sleeper: sleeper) do
          # This read happens AFTER the foreign writer committed, so it observes
          # ['foreign'] rather than the pre-contention []. Appending 'mine' keeps
          # both edits — the lost update is prevented.
          read = Owl::Tasks::Internal::TaskReader.read(tasks_root: tasks_root, task_id: 'TASK-0001')
          payload = read.value[:payload]
          payload['labels'] = payload['labels'] + ['mine']
          Owl::Tasks::Internal::AtomicYamlWriter.write(path: read.value[:path], payload: payload)
        end

        final = Owl::Tasks::Internal::TaskReader.read(tasks_root: tasks_root, task_id: 'TASK-0001')
        expect(final.value[:payload]['labels']).to eq(%w[foreign mine])
        expect(lock_file(root, 'TASK-0001')).not_to exist
      end
    end
  end
end
