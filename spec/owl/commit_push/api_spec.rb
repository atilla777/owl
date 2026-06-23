# frozen_string_literal: true

require 'owl/commit_push/api'
require 'owl/result'

RSpec.describe Owl::CommitPush::Api do
  def ok_outcome(stdout = '')
    Owl::CommitPush::Internal::GitRunner::Outcome.new(true, stdout, '')
  end

  def fail_outcome(stderr = 'boom', stdout = '')
    Owl::CommitPush::Internal::GitRunner::Outcome.new(false, stdout, stderr)
  end

  # A fully-stubbed git facade; pass overrides per scenario.
  def fake_git(overrides = {})
    defaults = {
      add_all: ok_outcome,
      status_porcelain: ok_outcome(" M lib/foo.rb\n"),
      unpushed?: ok_outcome("0\n"),
      commit: ok_outcome,
      pull_rebase: ok_outcome,
      push: ok_outcome,
      head_sha: ok_outcome("abc123\n")
    }
    object_double(Owl::CommitPush::Internal::GitRunner, **defaults, **overrides)
  end

  def fake_steps(status:, **overrides)
    defaults = {
      status: Owl::Result.ok(status: status),
      complete: Owl::Result.ok(step: { 'status' => 'done' }),
      mark_running: Owl::Result.ok(step: { 'status' => 'running' })
    }
    object_double(Owl::Steps::Api, **defaults, **overrides)
  end

  def fake_locks(acquire: Owl::Result.ok(token: 'tok'), release: Owl::Result.ok(released: true))
    object_double(Owl::Locks::Api, acquire: acquire, release: release)
  end

  def call(git:, steps:, locks:, message: 'Owl: deliver')
    described_class.commit_push(root: '/repo', task_id: 'TASK-0001', message: message,
                                git: git, locks: locks, steps: steps)
  end

  describe '.commit_push success (first run)' do
    it 'stages, flips done, commits, pulls and pushes a single commit' do
      git = fake_git
      steps = fake_steps(status: 'running')
      locks = fake_locks
      result = call(git: git, steps: steps, locks: locks)

      expect(result).to be_ok
      expect(result.value).to eq(task_id: 'TASK-0001', commit_sha: 'abc123', pushed: true)
      expect(steps).to have_received(:complete).with(root: '/repo', task_id: 'TASK-0001', step_id: 'commit_push')
      expect(git).to have_received(:add_all).twice
      expect(git).to have_received(:commit).with(root: '/repo', message: 'Owl: deliver')
      expect(locks).to have_received(:release).with(root: '/repo', name: 'git', token: 'tok')
    end
  end

  describe '.commit_push nothing_to_commit' do
    it 'returns nothing_to_commit without flipping done or locking' do
      git = fake_git(status_porcelain: ok_outcome(''))
      steps = fake_steps(status: 'running')
      locks = fake_locks
      result = call(git: git, steps: steps, locks: locks)

      expect(result).to be_err
      expect(result.code).to eq(:nothing_to_commit)
      expect(steps).not_to have_received(:complete)
      expect(locks).not_to have_received(:acquire)
    end
  end

  describe '.commit_push commit failure rolls back to running' do
    it 'marks the step running, creates no commit, and releases the lock' do
      git = fake_git(commit: fail_outcome('nothing staged'))
      steps = fake_steps(status: 'running')
      locks = fake_locks
      result = call(git: git, steps: steps, locks: locks)

      expect(result).to be_err
      expect(result.code).to eq(:commit_failed)
      expect(steps).to have_received(:mark_running).with(root: '/repo', task_id: 'TASK-0001', step_id: 'commit_push')
      expect(git).not_to have_received(:push)
      expect(locks).to have_received(:release)
    end
  end

  describe '.commit_push push failure keeps the commit (push_retryable)' do
    it 'returns push_retryable with the commit sha and does not roll back' do
      git = fake_git(push: fail_outcome('rejected'))
      steps = fake_steps(status: 'running')
      locks = fake_locks
      result = call(git: git, steps: steps, locks: locks)

      expect(result).to be_err
      expect(result.code).to eq(:push_retryable)
      expect(result.details).to include(commit_sha: 'abc123')
      expect(steps).not_to have_received(:mark_running)
      expect(locks).to have_received(:release)
    end

    it 'returns rebase_conflict when pull --rebase reports a conflict' do
      git = fake_git(pull_rebase: fail_outcome('CONFLICT (content): merge conflict'))
      steps = fake_steps(status: 'running')
      result = call(git: git, steps: steps, locks: fake_locks)

      expect(result).to be_err
      expect(result.code).to eq(:rebase_conflict)
      expect(git).not_to have_received(:push)
    end
  end

  describe '.commit_push idempotent retry' do
    it 'skips staging/commit and only re-attempts pull + push' do
      git = fake_git(status_porcelain: ok_outcome(''), unpushed?: ok_outcome("1\n"))
      steps = fake_steps(status: 'done')
      locks = fake_locks
      result = call(git: git, steps: steps, locks: locks)

      expect(result).to be_ok
      expect(result.value).to eq(task_id: 'TASK-0001', commit_sha: 'abc123', pushed: true)
      expect(git).not_to have_received(:add_all)
      expect(git).not_to have_received(:commit)
      expect(steps).not_to have_received(:complete)
      expect(git).to have_received(:push)
    end

    it 'reports push_retryable when the retry push still fails' do
      git = fake_git(status_porcelain: ok_outcome(''), unpushed?: ok_outcome("1\n"),
                     push: fail_outcome('still rejected'))
      steps = fake_steps(status: 'done')
      result = call(git: git, steps: steps, locks: fake_locks)

      expect(result).to be_err
      expect(result.code).to eq(:push_retryable)
    end
  end

  describe '.commit_push default dependencies' do
    it 'delegates to the transaction with the real git/locks/steps facades' do
      allow(Owl::CommitPush::Internal::Transaction).to receive(:call).and_return(Owl::Result.ok(pushed: true))

      result = described_class.commit_push(root: '/repo', task_id: 'TASK-0001', message: 'Owl: x')

      expect(result).to be_ok
      expect(Owl::CommitPush::Internal::Transaction).to have_received(:call).with(
        root: '/repo', task_id: 'TASK-0001', step_id: 'commit_push', message: 'Owl: x',
        git: Owl::CommitPush::Internal::GitRunner,
        locks: Owl::Locks::Api,
        steps: Owl::Steps::Api
      )
    end
  end
end
