---
status: passed
summary: "Wired the spec layer into the feature workflow: optional spec_delta artifact + deterministic owl spec merge (P4 apply + P5 trace gate), invoked by merge_docs; backward-compatible no-op for spec-less tasks; full suite 1394 ex / 0 failures, specs/api.rb 100%."
---

# Verification

## Summary

Implemented the optional `spec_delta` task artifact, the deterministic
`owl spec merge TASK-ID [--dry-run]` command (P4 delta apply + P5 trace
`--strict` gate), `Owl::Specs::Api.merge_task` / `Internal::TaskMerger`, and
updated the `feature` workflow's `merge_docs` context to invoke both
`owl publish` and `owl spec merge`. A task with no `spec_delta` sees ZERO
behavioural change (graceful `no_spec_delta` skip).

Workflow-declaration approach used: the PRIMARY approach validated cleanly —
`spec_delta` is declared as an OPTIONAL entry in the feature workflow's
`artifacts:` map (`type: spec_delta`, `storage.role: tasks`,
`path: {{task.id}}/spec_delta.md`) with NO step `creates:` it. The workflow
validator does not require a creating step for a declared artifact, so the
`uses_if_present` fallback was NOT needed (`owl workflow validate feature`
returns `valid: true`).

All filesystem access routes through `Owl::Storage::Api` / `Owl::Artifacts::Api`
(no raw File/Dir/Pathname in new code).

## Commands

- `bin/owl artifact-type validate spec_delta --json` -> `valid: true`
- `bin/owl workflow validate feature --json` -> `valid: true`
- Seed parity (active vs seed) — all identical:
  - `diff artifacts/spec_delta/artifact.yaml .owl/artifacts/spec_delta/artifact.yaml`
  - `diff artifacts/spec_delta/templates/default.md .owl/artifacts/spec_delta/templates/default.md`
  - `diff workflows/feature/workflow.yaml .owl/workflows/feature/workflow.yaml`
  - `diff workflows/feature/merge_docs.context.md .owl/workflows/feature/merge_docs.context.md`
- `bundle exec rspec spec/owl/specs/merge_task_spec.rb spec/owl/specs/internal/task_merger_spec.rb spec/owl/cli/spec_merge_command_spec.rb spec/owl/integration/merge_docs_spec_merge_spec.rb` -> 21 examples, 0 failures
- `bundle exec rspec` (full suite) -> 1394 examples, 0 failures, 1 pending
- `bundle exec rubocop <changed lib + new specs>` -> no offenses
- Manual smoke (throwaway /tmp project, since removed): dry-run (no write),
  real apply (writes), no-delta skip, gate-fail (ok:false, delta still applied),
  missing-domain, invalid_domain, propagated delta_conflict — all as designed.

## Outcomes

- `bin/owl artifact-type validate spec_delta` -> `valid: true`.
- `bin/owl workflow validate feature` -> `valid: true` (primary artifacts-map
  declaration; `uses_if_present` fallback not required).
- Full suite: 1394 examples, 0 failures, 1 pending. The full-suite process exit
  is non-zero ONLY because of the pre-existing `lib/owl/steps/api.rb` 99.16%
  SimpleCov gap (unrelated to this task).
- `lib/owl/specs/api.rb`: 100% line coverage (NOT listed under the SimpleCov
  "below 100%" report; only `steps/api.rb` is).
- RuboCop: clean on all changed/added files. The 2 remaining offenses in
  `spec/owl/cli/api_spec.rb` (lines 156, 427) pre-exist at HEAD (confirmed via
  `git stash`) and were not introduced here. Never ran `-A`.
- Backward-compat verified by `spec/owl/integration/merge_docs_spec_merge_spec.rb`:
  a spec-less task's merge is a clean no-op writing nothing under `specs/`, and
  the existing `owl publish` `no_publishable_step` no-op still holds.
- Tests cover: apply+trace ok; gate failure (untraced) -> ok:false with delta
  still applied; no-delta skip; dry-run no-write; missing-domain; invalid_domain;
  propagated `delta_conflict`; CLI exit codes; JSON and `--no-json` summaries.
- Updated 4 pre-existing seed-count tests from "seven" to "eight" seeded
  artifact types (adding `spec_delta`) and relaxed two assertions that required
  every seeded artifact to declare `required_sections` so the patterns-based
  `spec_delta` (which validates via `required_patterns`) is accepted.
- README.md was NOT dirtied by the suite this run; no throwaway `specs/<domain>`
  or tasks left in the repo (smoke project lived under `/tmp` and was removed).
- Known dry-run edge (documented in `TaskMerger`): under `--dry-run` the trace
  reflects the current on-disk spec (the delta is not written), so a dry-run for
  a brand-new domain whose spec does not yet exist would surface `spec_not_found`
  from P5. Not exercised by the seeded smoke/tests (they seed the domain first).
