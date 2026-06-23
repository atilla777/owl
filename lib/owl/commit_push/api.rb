# frozen_string_literal: true

require_relative '../locks/api'
require_relative '../steps/api'
require_relative 'internal/git_runner'
require_relative 'internal/transaction'

module Owl
  module CommitPush
    # Facade for the transactional `commit_push` step: stage every change,
    # record `commit_push: done`, then commit + pull --rebase + push under the
    # repo-scoped git lock — as one operation. The git / lock / step
    # dependencies default to the real facades and are injectable so the whole
    # flow is unit-testable without touching real git or the network.
    #
    # Returns `Owl::Result`:
    #   ok(task_id:, commit_sha:, pushed: true)
    #   err(:nothing_to_commit | :commit_failed | :push_retryable |
    #       :rebase_conflict | :lock_held | ...)
    #
    # The Api never prints and knows nothing about JSON.
    module Api
      module_function

      def commit_push(root:, task_id:, message:, step_id: 'commit_push',
                      git: Internal::GitRunner, locks: Owl::Locks::Api, steps: Owl::Steps::Api)
        Internal::Transaction.call(root: root, task_id: task_id, step_id: step_id,
                                   message: message, git: git, locks: locks, steps: steps)
      end
    end
  end
end
