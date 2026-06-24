---
status: passed
summary: "DeltaMerger.apply made idempotent (re-applied delta = no-op, genuine same-name/different-content still delta_conflict); honest unchanged counts threaded out; full rspec green, api.rb 100% gate green, rubocop clean, version bumped 0.15.0 → 0.15.1."
---

# Summary

Made `Owl::Specs::Internal::DeltaMerger.apply` idempotent so a retried
`owl spec merge` / `owl spec apply` of the same delta succeeds instead of
falsely erroring:

- **`add`** — for each ADDED block: no existing name → append `normalize(block)`
  (unchanged); existing name with `requirements[index] == normalize(block)` →
  idempotent no-op (NOT `delta_conflict`); existing name with different
  normalized content → `delta_conflict` (genuine, unchanged).
- **`remove`** — a name already absent is an already-removed no-op (NOT
  `delta_target_missing`); present → deleted as before.
- **`modify`** — left semantically unchanged: re-set to the same content is a
  no-op (now counted), `MODIFY` of an absent target still `delta_target_missing`.
- **Honest counts** — `add`/`remove`/`modify` now return
  `{ requirements:, unchanged: }`; `apply` aggregates an `:unchanged` summary
  (`{ added:, modified:, removed: }`) into the returned model.
  `MergeEngine#counts(ops, unchanged)` now reports `applied` as truly-applied
  changes (declared ops minus no-ops) and surfaces no-ops separately as
  `unchanged`. `Specs::Api#diff`/`apply` pass `unchanged` through. A no-op is
  never counted as an applied change.

Files changed: `lib/owl/specs/internal/delta_merger.rb`,
`lib/owl/specs/internal/merge_engine.rb`, `lib/owl/specs/api.rb`,
`lib/owl/version.rb` (0.15.0 → 0.15.1, PATCH), `CHANGELOG.md`,
`spec/owl/specs/internal/delta_merger_spec.rb`, `spec/owl/specs/apply_spec.rb`.

# Commands

- `bundle exec rspec spec/owl/specs/` — scoped spec run.
- `bundle exec rspec` — full suite + coverage gate.
- `git checkout README.md` — known README test-isolation wart (no-op this run).
- `bundle exec rubocop <5 changed files>` — lint.

# Outcomes

- `bundle exec rspec spec/owl/specs/`: 99 examples, 0 failures.
- `bundle exec rspec` (full): **1940 examples, 0 failures, 1 pending** (the
  pre-existing storage concurrent-write pending), exit 0. Line coverage 97.0%;
  **no "Public API files below 100%" report printed → the `**/api.rb` 100% gate
  is green** (including `lib/owl/specs/api.rb`).
- `bundle exec rubocop` on the 5 changed files: **no offenses detected** (net-zero).
- Version bumped 0.15.0 → 0.15.1; CHANGELOG top entry added under `### Fixed`.
  `Gemfile.lock` updated to `owl-cli (0.15.1)` (path gem, expected).

New / adjusted tests:
- Unit (`delta_merger_spec.rb`): idempotent re-ADD = no-op (unchanged.added 1);
  same-name/different-content ADD = `delta_conflict`; MODIFY to same content =
  no-op (unchanged.modified 1); genuine MODIFY counted as applied; REMOVE of
  absent name = no-op (unchanged.removed 1); rewrote the old "REMOVED absent →
  target_missing" and "case-sensitive via REMOVE" tests (the former contradicted
  the new no-op contract; case-sensitivity now asserted via MODIFY, which still
  errors on an absent target); zero-unchanged on a genuine add.
- Integration (`apply_spec.rb`): full `Owl::Specs::Api.apply` run TWICE on the
  same delta — second run succeeds (not `delta_conflict`), reports
  `applied: {added:0,…}` + `unchanged: {added:1,…}`, and the on-disk spec is
  **byte-identical** to the first apply.

# Not run

- Live `bin/owl spec merge` CLI smoke from the plan — covered equivalently by the
  in-process `Owl::Specs::Api.apply` double-merge integration test (the CLI is a
  thin wrapper over the same API).
- No manual end-to-end `merge_docs` trace-gate run; the task-level idempotency
  (`already_merged` status-flip) path is already covered by existing
  `merge_task_idempotency_spec.rb` and is orthogonal to this engine fix.

# Failures or blockers

None.

# Residual risks

- **Honest-counts contract scope.** I changed `applied` to mean truly-applied
  net changes (declared minus no-ops) and ADDED a new additive `unchanged`
  field, rather than a broad rename/refactor. For genuine (first-time) merges the
  `applied` numbers are identical to before, and the only case where they now
  differ (a no-op re-apply) previously raised an error so no consumer ever
  observed those numbers — hence treated as back-compat / PATCH. The CLI
  `spec merge`/`spec apply`/`spec diff` renderers read `applied` and are
  unaffected; they do not yet print `unchanged` (see follow-ups).
- The `:unchanged` summary rides along as an extra key on the merged spec model
  returned by `apply`; `SpecDocument.serialize` reads only
  `frontmatter/preamble/requirements/tail`, so it is inert for serialization and
  round-trips harmlessly.
