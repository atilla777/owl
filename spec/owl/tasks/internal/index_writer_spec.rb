# frozen_string_literal: true

require 'stringio'

require 'owl/tasks/api'
require 'owl/tasks/internal/index_writer'
require 'owl/tasks/internal/paths'
require 'owl/locks/api'
require 'owl/cli/internal/commands/init'

# Regression coverage for TASK-0021: every write of `tasks/index.yaml` must be
# serialized under the repo-scoped `Owl::Locks` lock named "index" so concurrent
# create/archive/delete/rebuild from different sessions cannot lose updates.
RSpec.describe Owl::Tasks::Internal::IndexWriter do
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

  def paths(root)
    Owl::Tasks::Internal::Paths.resolve(root: root).value
  end

  def lock_file(root)
    Pathname.new("#{root}/.owl/local/index.lock")
  end

  def task_ids(root)
    Owl::Tasks::Api.list(root: root).value[:tasks].map { |task| task['task_id'] }
  end

  describe '.rebuild' do
    it 'writes the index and releases the index lock' do
      with_tmp_project do |root|
        seed(root)
        Owl::Tasks::Api.create(root: root, workflow: 'feature', title: 't')

        p = paths(root)
        result = described_class.rebuild(root: root, tasks_root: p[:tasks], index_path: p[:index])

        expect(result).to be_ok
        expect(result.value[:tasks].map { |t| t['id'] }).to eq(['TASK-0001'])
        expect(lock_file(root)).not_to exist
      end
    end

    it 'releases the lock even when the underlying rebuild raises (leaf lock)' do
      with_tmp_project do |root|
        seed(root)
        p = paths(root)
        allow(Owl::Tasks::Internal::IndexRebuilder).to receive(:rebuild).and_raise(RuntimeError, 'boom')

        expect do
          described_class.rebuild(root: root, tasks_root: p[:tasks], index_path: p[:index])
        end.to raise_error(RuntimeError, 'boom')
        expect(lock_file(root)).not_to exist
      end
    end

    it 'returns the lock error without rebuilding when acquisition fails' do
      with_tmp_project do |root|
        seed(root)
        p = paths(root)
        # An unrecognised backend makes Locks::Api.acquire fail with a non-recoverable
        # error code, so .acquire returns immediately and the index is never rebuilt.
        write("#{root}/.owl/config.yaml",
              File.read("#{root}/.owl/config.yaml") + "settings:\n  storage:\n    backend: imaginary\n")
        allow(Owl::Tasks::Internal::IndexRebuilder).to receive(:rebuild).and_call_original

        result = described_class.rebuild(root: root, tasks_root: p[:tasks], index_path: p[:index])
        expect(result).to be_err
        expect(result.code).to eq(:unknown_backend)
        expect(Owl::Tasks::Internal::IndexRebuilder).not_to have_received(:rebuild)
      end
    end
  end

  describe '.acquire (serialization)' do
    let(:clock) { class_double(Time) }

    it 'times out with lock_held when a foreign holder never releases' do
      with_tmp_project do |root|
        seed(root)
        Owl::Locks::Api.acquire(root: root, name: 'index', token: 'foreign')
        now = Time.utc(2026, 1, 1, 12, 0, 0)
        # Clock has already passed the deadline on the second read, so the single
        # retry exits with the recoverable lock_held error.
        allow(clock).to receive(:now).and_return(now, now + described_class::ACQUIRE_TIMEOUT_SECONDS + 1)

        result = described_class.acquire(root: root, locks: Owl::Locks::Api, clock: clock, sleeper: ->(_s) {})
        expect(result).to be_err
        expect(result.code).to eq(:lock_held)
      end
    end

    it 'retries and acquires once the foreign holder releases (sleeper drives the release)' do
      with_tmp_project do |root|
        seed(root)
        acquire = Owl::Locks::Api.acquire(root: root, name: 'index', token: 'foreign')
        now = Time.utc(2026, 1, 1, 12, 0, 0)
        allow(clock).to receive(:now).and_return(now)
        released = false
        sleeper = lambda do |_s|
          Owl::Locks::Api.release(root: root, name: 'index', token: acquire.value[:token])
          released = true
        end

        result = described_class.acquire(root: root, locks: Owl::Locks::Api, clock: clock, sleeper: sleeper)
        expect(released).to be(true)
        expect(result).to be_ok
        # Release what we just acquired to leave the roster clean.
        Owl::Locks::Api.release(root: root, name: 'index', token: result.value[:token])
      end
    end
  end

  describe 'single-session chain (no self-deadlock, no lost updates)' do
    it 'create -> create -> delete keeps every surviving roster entry' do
      with_tmp_project do |root|
        seed(root)
        Owl::Tasks::Api.create(root: root, workflow: 'feature', title: 'A')
        Owl::Tasks::Api.create(root: root, workflow: 'feature', title: 'B')
        expect(task_ids(root)).to contain_exactly('TASK-0001', 'TASK-0002')

        Owl::Tasks::Api.delete(root: root, task_id: 'TASK-0001')
        expect(task_ids(root)).to eq(['TASK-0002'])
        expect(lock_file(root)).not_to exist
      end
    end
  end
end
