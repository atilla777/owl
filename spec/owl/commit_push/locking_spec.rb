# frozen_string_literal: true

require 'owl/commit_push/api'
require 'owl/result'

RSpec.describe 'owl commit-push locking' do
  def ok_outcome(stdout = '')
    Owl::CommitPush::Internal::GitRunner::Outcome.new(true, stdout, '')
  end

  def happy_git
    object_double(
      Owl::CommitPush::Internal::GitRunner,
      add_all: ok_outcome, status_porcelain: ok_outcome(" M lib/foo.rb\n"), unpushed?: ok_outcome("0\n"),
      commit: ok_outcome, pull_rebase: ok_outcome, push: ok_outcome, head_sha: ok_outcome("abc123\n")
    )
  end

  def running_steps
    object_double(
      Owl::Steps::Api,
      status: Owl::Result.ok(status: 'running'),
      complete: Owl::Result.ok(step: {}),
      mark_running: Owl::Result.ok(step: {})
    )
  end

  def commit_push(git:, steps:, locks:)
    Owl::CommitPush::Api.commit_push(root: '/repo', task_id: 'TASK-0001', message: 'Owl: x',
                                     git: git, locks: locks, steps: steps)
  end

  it "acquires and releases the shared 'git' lock with the issued token" do
    locks = object_double(Owl::Locks::Api, acquire: Owl::Result.ok(token: 'tok'),
                                           release: Owl::Result.ok(released: true))

    result = commit_push(git: happy_git, steps: running_steps, locks: locks)

    expect(result).to be_ok
    expect(locks).to have_received(:acquire).with(root: '/repo', name: 'git')
    expect(locks).to have_received(:release).with(root: '/repo', name: 'git', token: 'tok')
  end

  it 'returns the recoverable lock_held error and never releases when the lock is held' do
    locks = object_double(
      Owl::Locks::Api,
      acquire: Owl::Result.err(code: :lock_held, message: 'held', error_class: :recoverable),
      release: Owl::Result.ok(released: true)
    )

    result = commit_push(git: happy_git, steps: running_steps, locks: locks)

    expect(result).to be_err
    expect(result.code).to eq(:lock_held)
    expect(result.error_class).to eq(:recoverable)
    expect(locks).not_to have_received(:release)
  end

  it 'leaves the step running on lock_held — the done flip never happens before the lock' do
    steps = running_steps
    git = happy_git
    locks = object_double(
      Owl::Locks::Api,
      acquire: Owl::Result.err(code: :lock_held, message: 'held', error_class: :recoverable),
      release: Owl::Result.ok(released: true)
    )

    commit_push(git: git, steps: steps, locks: locks)

    # A lock_held is a pre-commit failure: the step is never flipped to done and
    # nothing is committed (the flip happens only AFTER the lock is acquired).
    expect(steps).not_to have_received(:complete)
    expect(git).not_to have_received(:commit)
  end

  it 'releases the lock in an ensure even when a git call raises' do
    git = happy_git
    allow(git).to receive(:commit).and_raise(StandardError, 'kaboom')
    locks = object_double(Owl::Locks::Api, acquire: Owl::Result.ok(token: 'tok'),
                                           release: Owl::Result.ok(released: true))

    expect { commit_push(git: git, steps: running_steps, locks: locks) }
      .to raise_error(StandardError, 'kaboom')
    expect(locks).to have_received(:release).with(root: '/repo', name: 'git', token: 'tok')
  end
end
