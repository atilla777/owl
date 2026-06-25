# frozen_string_literal: true

require 'tmpdir'
require 'pathname'
require 'fileutils'
require 'open3'

require 'owl/commit_push/internal/git_runner'

# Exercises the new scoped-staging / index-probe primitives against a REAL git
# repo so the `:(exclude)` magic pathspec and the `git diff --cached --quiet`
# exit-code interpretation are verified end-to-end, not just mocked.
RSpec.describe Owl::CommitPush::Internal::GitRunner do
  let(:repo) do
    path = Pathname.new(Dir.mktmpdir('owl-git-runner'))
    run_git(path.to_s, 'init', '--initial-branch=main')
    run_git(path.to_s, 'config', 'user.email', 'test@example.com')
    run_git(path.to_s, 'config', 'user.name', 'Test')
    path
  end

  after { FileUtils.remove_entry(repo.to_s) if repo.directory? }

  def run_git(dir, *args)
    _out, _err, status = Open3.capture3('git', *args, chdir: dir)
    raise "git #{args.join(' ')} failed" unless status.success?
  end

  def write(root, rel, content = 'x')
    path = root.join(rel)
    path.dirname.mkpath
    path.write(content)
  end

  def staged_paths(root)
    out, = Open3.capture3('git', 'diff', '--cached', '--name-only', chdir: root.to_s)
    out.split("\n")
  end

  describe '.add_scoped' do
    it 'stages everything (git add -A) when exclude is empty' do
      write(repo, 'lib/foo.rb')
      write(repo, 'tasks/TASK-0002/task.yaml')

      outcome = described_class.add_scoped(root: repo, exclude: [])

      expect(outcome.ok).to be(true)
      expect(staged_paths(repo)).to include('lib/foo.rb', 'tasks/TASK-0002/task.yaml')
    end

    it 'treats a nil exclude like an empty one (git add -A)' do
      write(repo, 'lib/foo.rb')

      described_class.add_scoped(root: repo, exclude: nil)

      expect(staged_paths(repo)).to include('lib/foo.rb')
    end

    it 'keeps the excluded task dirs out of the index while staging the rest' do
      write(repo, 'lib/foo.rb')
      write(repo, 'tasks/TASK-0001/task.yaml')
      write(repo, 'tasks/TASK-0002/task.yaml')
      write(repo, 'tasks/TASK-0003/task.yaml')

      outcome = described_class.add_scoped(root: repo, exclude: ['tasks/TASK-0002', 'tasks/TASK-0003'])

      expect(outcome.ok).to be(true)
      staged = staged_paths(repo)
      expect(staged).to include('lib/foo.rb', 'tasks/TASK-0001/task.yaml')
      expect(staged).not_to include('tasks/TASK-0002/task.yaml', 'tasks/TASK-0003/task.yaml')
    end
  end

  describe '.index_dirty?' do
    it 'reports ok=true (empty index) when nothing is staged' do
      write(repo, 'lib/foo.rb') # untracked, NOT staged

      expect(described_class.index_dirty?(root: repo).ok).to be(true)
    end

    it 'reports ok=false (non-empty index) when something is staged' do
      write(repo, 'lib/foo.rb')
      run_git(repo.to_s, 'add', 'lib/foo.rb')

      expect(described_class.index_dirty?(root: repo).ok).to be(false)
    end
  end
end
