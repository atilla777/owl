---
status: passed
summary: owl publish now accepts a harness-pre-started (running) publishing step; specs and RuboCop green; version bumped 1.1.2 -> 1.1.3.
---

## Summary

Fixed the gate-ordering asymmetry in `owl publish`. The orchestrator's
execution harness pre-starts every step (`owl step start`) before running its
body, so a `publishes:`-bearing step (e.g. `merge_docs`) is `running` at
publish time. `Owl::Publish::Internal::StepGate` previously accepted only
`ready`/`done` and rejected the pre-started step with `publish_step_not_ready`.
The gate now also accepts `running`, analogous to how `commit-push` already
treats a pre-started step. Genuinely not-runnable steps (`pending`/blocked, not
in the ready set) are still rejected, and the error's `acceptable_statuses`
detail reflects the widened whitelist. Added RSpec coverage, bumped the patch
version, and recorded a CHANGELOG entry.

## Commands

- `bundle exec rspec spec/owl/publish/`
- `bundle exec rubocop lib/owl/publish/internal/step_gate.rb lib/owl/version.rb spec/owl/publish/api_spec.rb`

## Outcomes

- Files changed:
  - `lib/owl/publish/internal/step_gate.rb` — `ACCEPTABLE_STATUSES` widened to
    `%w[ready running done]`; early `Result.ok(status: 'running', ...)` return
    when stored status is `running`.
  - `spec/owl/publish/api_spec.rb` — two new examples: (a) publish succeeds when
    the publishing step's stored status is `running` (asserts `be_ok`,
    `step_status == 'running'`, target `created`); (b) publish still fails with
    `publish_step_not_ready` for a `pending` step not in the ready set (asserts
    `current_status == 'pending'` and `acceptable_statuses == %w[ready running
    done]`).
  - `lib/owl/version.rb` — `1.1.2` -> `1.1.3` (patch, back-compat fix).
  - `CHANGELOG.md` — new `[1.1.3]` Fixed entry describing the publish gate fix.
- `bundle exec rspec spec/owl/publish/`: **40 examples, 0 failures**.
- `bundle exec rubocop` on the changed files: **3 files inspected, no offenses
  detected**.

## Not run

Full `bundle exec rspec` suite was not run; the change is localized to
`lib/owl/publish/**` and the publish spec directory exercises the touched code
path directly. RuboCop was scoped to the changed files (the full-repo run was
already green per 1.1.2 / TASK-0048).

## Failures or blockers

None. The known repo wart (full-suite SimpleCov coverage gate exiting non-zero
on partial runs) did not trigger: the scoped publish run finished `40 examples,
0 failures` and exited cleanly (the 47.37% line in the output is the
informational coverage report, not the gate, which only fires on a full-suite
run since 1.1.2).

## Residual risks

None of note. The change is additive (widens an accepted-status whitelist);
no JSON response shape, schema, or seeded template changed. `commit-push` was
intentionally left untouched (already expects `running`). The `ready` and
`done` paths retain their existing specs, so no regression to prior behavior.
