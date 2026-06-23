# frozen_string_literal: true

require_relative '../../result'

module Owl
  module CommitPush
    module Internal
      # The transactional core of `owl commit-push`. Encapsulates the ordered
      # sequence
      #
      #   resolve status → idempotent-retry branch → acquire git lock → stage →
      #   nothing-to-commit guard → flip `commit_push: done` → re-stage →
      #   commit → pull --rebase → push → release lock
      #
      # as one operation. Failure semantics:
      #   * before `git commit` → step rolled back to `running`, no commit;
      #   * commit ok but pull/push fail → commit kept, command is idempotent
      #     (re-run takes the retry branch and only re-attempts pull + push).
      #
      # All git / lock / step effects flow through injected facades so the
      # whole flow is unit-testable without real git or the network.
      module Transaction
        # Reuse the same advisory lock name as `owl git lock` so manual locks
        # and `owl commit-push` serialize against each other.
        LOCK_NAME = 'git'

        module_function

        def call(root:, task_id:, step_id:, message:, git:, locks:, steps:)
          retrying = retry?(git: git, steps: steps, root: root, task_id: task_id, step_id: step_id)

          unless retrying
            guard = stage_and_guard(git: git, root: root, task_id: task_id)
            return guard if guard.is_a?(Owl::Result::Err)
          end

          publish(git: git, locks: locks, steps: steps, root: root,
                  task_id: task_id, step_id: step_id, message: message, retrying: retrying)
        end

        # Stage the working tree and fail fast on an empty delivery — BEFORE the
        # lock and BEFORE any step mutation, so a no-op delivery never touches
        # the push lock or the step status. Staging is idempotent. Returns `nil`
        # on success or a `nothing_to_commit` error.
        def stage_and_guard(git:, root:, task_id:)
          git.add_all(root: root)
          return nothing_to_commit(task_id) if clean_tree?(git, root)

          nil
        end

        # Acquire the push lock BEFORE flipping the step to `done` — so a
        # `lock_held` (a pre-commit failure) leaves `commit_push` untouched at
        # `running`, per the brief's "any failure before commit → running" rule.
        # The flip + re-stage happen under the lock so the flip still rides in
        # the same commit. (Staging + the empty-delivery guard already ran
        # before the lock in `stage_and_guard`.)
        def publish(git:, locks:, steps:, root:, task_id:, step_id:, message:, retrying:)
          lock = locks.acquire(root: root, name: LOCK_NAME)
          return lock if lock.err?

          token = lock.value[:token]

          unless retrying
            flip = flip_done(git: git, steps: steps, root: root, task_id: task_id, step_id: step_id)
            return flip if flip.is_a?(Owl::Result::Err)
          end

          committed = run_commit(git: git, steps: steps, root: root,
                                 task_id: task_id, step_id: step_id, message: message, retrying: retrying)
          return committed if committed.is_a?(Owl::Result::Err)

          finish_push(git: git, root: root, task_id: task_id)
        ensure
          locks.release(root: root, name: LOCK_NAME, token: token) if token
        end

        # Under the lock: flip the step to `done` and re-stage so the flip rides
        # in the same commit. Returns `nil` on success or the `Err` from a failed
        # `complete` (which leaves the step at `running`).
        def flip_done(git:, steps:, root:, task_id:, step_id:)
          flip = steps.complete(root: root, task_id: task_id, step_id: step_id)
          return flip if flip.err?

          git.add_all(root: root)
          nil
        end

        # Create the commit unless we are on the retry branch (commit already
        # exists). A failed commit rolls the step back to `running` and reports
        # `commit_failed`; otherwise returns `nil`.
        def run_commit(git:, steps:, root:, task_id:, step_id:, message:, retrying:)
          return nil if retrying

          outcome = git.commit(root: root, message: message)
          return nil if outcome.ok

          steps.mark_running(root: root, task_id: task_id, step_id: step_id)
          commit_failed(outcome)
        end

        def finish_push(git:, root:, task_id:)
          pull = git.pull_rebase(root: root)
          return push_failure(pull, git, root, task_id) unless pull.ok

          push = git.push(root: root)
          return push_failure(push, git, root, task_id) unless push.ok

          Owl::Result.ok(task_id: task_id.to_s, commit_sha: head_sha(git, root), pushed: true)
        end

        def retry?(git:, steps:, root:, task_id:, step_id:)
          step_done?(steps, root, task_id, step_id) &&
            clean_tree?(git, root) &&
            unpushed?(git, root)
        end

        def step_done?(steps, root, task_id, step_id)
          res = steps.status(root: root, task_id: task_id, step_id: step_id)
          res.ok? && res.value[:status].to_s == 'done'
        end

        def clean_tree?(git, root)
          out = git.status_porcelain(root: root)
          out.ok && out.stdout.strip.empty?
        end

        def unpushed?(git, root)
          out = git.unpushed?(root: root)
          out.ok && out.stdout.strip.to_i.positive?
        end

        def head_sha(git, root)
          out = git.head_sha(root: root)
          out.ok ? out.stdout.strip : nil
        end

        def push_failure(outcome, git, root, task_id)
          sha = head_sha(git, root)
          conflict = "#{outcome.stdout}#{outcome.stderr}".downcase.include?('conflict')
          code = conflict ? :rebase_conflict : :push_retryable
          message =
            if conflict
              'pull --rebase reported a conflict; resolve it, then re-run owl commit-push'
            else
              'commit created; push failed — re-run owl commit-push to retry'
            end
          Owl::Result.err(code: code, message: message,
                          details: { task_id: task_id.to_s, commit_sha: sha }, error_class: :recoverable)
        end

        def nothing_to_commit(task_id)
          Owl::Result.err(
            code: :nothing_to_commit,
            message: 'Nothing to commit; staging produced no changes. commit_push left running.',
            details: { task_id: task_id.to_s }, error_class: :validation
          )
        end

        def commit_failed(outcome)
          Owl::Result.err(
            code: :commit_failed,
            message: 'git commit failed; commit_push rolled back to running, no commit created.',
            details: { stderr: outcome.stderr }, error_class: :recoverable
          )
        end
      end
    end
  end
end
