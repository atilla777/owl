---
status: passed
summary: Deterministic structural delta-merge engine (SpecDocument/SpecDelta/DeltaMerger + TextDiff + MergeEngine) and owl spec apply/diff shipped; full suite green (1353 ex, 0 failures), specs/api.rb at 100% line coverage, RuboCop clean on changed files.
---

# Summary

Implemented Problem 4: a deterministic structural delta-merge engine plus the
`owl spec apply` / `owl spec diff` CLI, all under `Owl::Specs`. A spec body is
parsed into a byte-stable RequirementBlock model, a delta document is parsed into
ADDED/MODIFIED/REMOVED operations, and the merge is applied in a fixed order
(REMOVED → MODIFIED → ADDED) entirely in memory. The merged body is re-validated
against the `spec` artifact type before any write; a would-be-invalid merge
returns `merge_would_invalidate` and writes nothing. Create-from-absent scaffolds
a minimal spec for ADDED-only deltas against a missing spec; MODIFIED/REMOVED
against a missing spec returns `spec_not_found`. A dependency-free in-process LCS
diff provides the human preview. The feature workflow's `merge_docs` step was
deliberately NOT rewired (out of scope, per design).

Files added: `lib/owl/specs/internal/{spec_document,spec_delta,delta_merger,text_diff,merge_engine}.rb`,
`lib/owl/cli/internal/commands/{spec_apply,spec_diff}.rb`, and the test files
`spec/owl/specs/internal/{spec_document,spec_delta,delta_merger}_spec.rb`,
`spec/owl/specs/apply_spec.rb`, `spec/owl/cli/spec_apply_diff_command_spec.rb`.
Files changed: `lib/owl/specs/api.rb` (added `diff`/`apply`), `lib/owl/cli/api.rb`
(`dispatch_spec` + requires), `lib/owl/cli/internal/help_text.rb`,
`lib/owl/cli/internal/commands/task_support.rb` (added `expand_path` path-utility),
`lib/owl/validation/internal/artifact_runner.rb` (extracted `validate_body` for
in-memory validation).

# Commands

```
# Unit + integration specs for the new engine and CLI
bundle exec rspec spec/owl/specs spec/owl/cli/spec_apply_diff_command_spec.rb spec/owl/cli/spec_command_spec.rb
#   => 76 examples, 0 failures

# Full suite (coverage gate runs at_exit)
bundle exec rspec
#   => 1353 examples, 0 failures, 1 pending
#   => Public API files below 100% line coverage: lib/owl/steps/api.rb: 99.16% (pre-existing, unrelated)

# RuboCop on every changed file (no -A)
bundle exec rubocop lib/owl/specs \
  lib/owl/cli/internal/commands/spec_apply.rb lib/owl/cli/internal/commands/spec_diff.rb \
  lib/owl/cli/internal/commands/task_support.rb lib/owl/cli/api.rb \
  lib/owl/cli/internal/help_text.rb lib/owl/validation/internal/artifact_runner.rb \
  spec/owl/specs spec/owl/cli/spec_apply_diff_command_spec.rb
#   => 21 files inspected, no offenses detected

# Manual CLI smoke (seeded specs/billing/spec.md + ADDED delta)
bin/owl spec diff  billing --delta d.md --root <proj> --json   # preview, no write
bin/owl spec apply billing --delta d.md --root <proj> --dry-run --json  # no write
bin/owl spec apply billing --delta d.md --root <proj> --json   # writes merged spec
bin/owl spec validate billing --root <proj> --json             # valid:true
bin/owl spec apply billing --delta d.md --root <proj> --json   # delta_conflict, no write
```

# Outcomes

- New + touched specs: 76 examples, 0 failures.
- Full suite: 1353 examples, 0 failures, 1 pending.
- Coverage: `lib/owl/specs/api.rb` at 100% line coverage (absent from the gate's
  below-100% list). The only public-API file under 100% is the pre-existing
  `lib/owl/steps/api.rb` at 99.16%, unrelated to this task — the expected
  non-zero full-suite exit from the coverage gate.
- Determinism: `spec/owl/specs/apply_spec.rb` "is deterministic — applying the
  same delta twice yields identical bytes" passes (the engine is a pure
  function of (spec, delta)).
- Round-trip identity: `spec/owl/specs/internal/spec_document_spec.rb`
  "serialize is the exact inverse of parse for an untouched spec" passes;
  block-boundary fixtures (adjacent requirements, trailing `## ` section,
  nested `#### Scenario`, fenced pseudo-heading) covered.
- merge_would_invalidate: apply of a MODIFIED requirement that drops its
  scenario returns `merge_would_invalidate` with the `requirement_without_scenario`
  violation and leaves the on-disk spec byte-identical (write aborted). Verified
  at both Api and CLI levels.
- Structured errors exercised end-to-end: `delta_conflict`,
  `delta_target_missing`, `invalid_delta` (unknown section / duplicate name /
  empty), `spec_not_found`, `delta_not_found`, `invalid_domain`.
- RuboCop clean on all changed files (no `-A` used).
- README.md was NOT dirtied by the suite this run (`git status --short README.md`
  clean); no restore needed.
- Constitution `no_direct_fs` meta-spec stays green: path expansion for the
  `--delta` argument lives in the allowlisted `task_support.rb` path-utility; all
  spec I/O goes through `Owl::Storage::Api`.
