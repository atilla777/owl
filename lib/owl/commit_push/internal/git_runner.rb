# frozen_string_literal: true

require 'open3'

module Owl
  module CommitPush
    module Internal
      # Default git command runner for `owl commit-push`. A thin wrapper over
      # `Open3.capture3` (mirrors `Owl::Upgrade::Internal::ShellRunner`),
      # injectable so the transaction can be unit-tested without touching real
      # git or the network. Every method runs `git` with `chdir: root` and
      # returns an `Outcome(ok, stdout, stderr)`.
      module GitRunner
        Outcome = Struct.new(:ok, :stdout, :stderr)

        module_function

        def add_all(root:)
          run(%w[git add -A], root)
        end

        def commit(root:, message:)
          run(['git', 'commit', '-m', message.to_s], root)
        end

        def pull_rebase(root:)
          run(%w[git pull --rebase], root)
        end

        def push(root:)
          run(%w[git push], root)
        end

        def status_porcelain(root:)
          run(%w[git status --porcelain], root)
        end

        # Commits ahead of the upstream branch. `stdout` carries the count from
        # `git rev-list @{u}..HEAD --count`; `ok` is false when there is no
        # upstream configured.
        def unpushed?(root:)
          run(['git', 'rev-list', '@{u}..HEAD', '--count'], root)
        end

        def head_sha(root:)
          run(%w[git rev-parse HEAD], root)
        end

        def run(cmd, root)
          stdout, stderr, status = Open3.capture3(*cmd, chdir: root.to_s)
          Outcome.new(status.success?, stdout, stderr)
        rescue StandardError => e
          Outcome.new(false, '', e.message)
        end
      end
    end
  end
end
