---
status: resolved
summary: "P2-B idempotent spec merge accepted: DeltaMerger.apply no-ops a re-applied delta via normalized equality, genuine same-name/different-content still delta_conflict, MODIFY of absent target still delta_target_missing; honest unchanged counts back-compat; rspec 1940/0, api.rb 100% gate green, rubocop net-zero."
verdict: accepted
ready: true
---

# Summary

Reviewed the `implement` diff for TASK-0029 (hotfix, P2-B) against the brief
and plan. The change makes `Owl::Specs::Internal::DeltaMerger.apply` idempotent
without weakening genuine-conflict / missing-target detection, threads honest
no-op (`unchanged`) counts through `merge_engine`/`specs/api`, bumps
`Owl::VERSION` 0.15.0 → 0.15.1 (PATCH) and adds a CHANGELOG entry.

Files reviewed: `lib/owl/specs/internal/delta_merger.rb`,
`lib/owl/specs/internal/merge_engine.rb`, `lib/owl/specs/api.rb`,
`lib/owl/version.rb`, `CHANGELOG.md`, `spec/owl/specs/apply_spec.rb`,
`spec/owl/specs/internal/delta_merger_spec.rb` (the `tasks/index.yaml` working
change and the deferred CLI `unchanged` printing are out of scope per the step
brief).

# Findings

All brief/plan acceptance points hold; no defects found.

- **`add` equality check is correct (the highest-risk item).** Branch order is
  `index.nil?` → append `normalize(block)`; `requirements[index] == normalized`
  → no-op (`unchanged += 1`); else → `conflict(name)`. The comparison is against
  the STORED normalized requirement (`requirements[index]`) versus
  `normalize(block)`, i.e. normalized-vs-normalized. A same-content re-apply
  matches (no-op); a real content change does NOT match → still
  `:delta_conflict`. Constructed both cases (delta_merger_spec
  "re-ADDED identical → no-op" and "ADDED different content → delta_conflict",
  plus the pre-existing model_for('A')+block('A') conflict at line 46): the
  branch picks correctly. A loose-equality swallow of a genuine change is NOT
  present.
- **`remove` idempotent, no semantic loss.** Absent name → `unchanged += 1`
  no-op (not `:delta_target_missing`); present → `delete_at`. Both branches
  covered.
- **`modify` unchanged-behavior preserved.** Re-set to same content increments
  `unchanged` but still assigns (harmless); MODIFY of an absent target STILL
  returns `:delta_target_missing` (line 68, `return ... unless index`). Not
  accidentally made to swallow missing targets — confirmed by the rewritten
  case-sensitivity test (a different-case MODIFY target errors).
- **Idempotency proven with byte-stability.** `apply_spec.rb` runs
  `Owl::Specs::Api.apply` TWICE on the same delta against a real on-disk spec:
  the first run writes the file (`applied {added:1}`), the second run reads it
  back from disk (`base_model` → `SpecDocument.parse`), succeeds (NOT
  `delta_conflict`), reports `applied {added:0}` + `unchanged {added:1}`, and
  asserts `spec.read == after_first` — a true serialize→reparse→normalize
  round-trip byte-stability proof, not just an in-memory same-object compare.
- **Honest counts, back-compat.** `counts(ops, unchanged)` returns
  `applied = declared ops − no-ops`; `unchanged` cannot exceed declared length
  (no-ops are only incremented while iterating `delta[:added|modified|removed]`,
  the same lists `ops` counts), so `applied` never goes negative. For a genuine
  first-time merge `unchanged == 0`, so `applied` is byte-identical to the prior
  contract; the only divergent case (no-op re-apply) previously raised, so no
  consumer ever observed those numbers. `unchanged` is purely additive and is
  inert for `SpecDocument.serialize` (reads only frontmatter/preamble/
  requirements/tail). PATCH bump is correct.
- **No semantic drift.** Delta/spec format and operation semantics are otherwise
  unchanged; only the false-error removal + additive counts.

# Resolution

Accepted as-is. Every checklist branch is exercised by the spec changes:
`add` (append / no-op / conflict), `remove` (delete / no-op), `modify`
(applied / no-op / target_missing), the `apply` aggregation, and the
disk-round-trip double-merge integration test.

Checks run on this review:
- `bundle exec rspec` — **1940 examples, 0 failures, 1 pending** (pre-existing
  storage concurrent-write pending), exit 0. No "Public API files below 100%"
  report printed → the `lib/owl/**/api.rb` 100% gate is green (incl.
  `lib/owl/specs/api.rb`, whose two new `unchanged:` lines are covered by the
  `apply`/`diff` paths).
- `git checkout README.md` — clean, 0 paths updated (no test-isolation drift
  this run).
- `bundle exec rubocop` on the 6 changed files — no offenses (net-zero).

# Remediation

None required.

# Residual risks

- **CLI does not yet print `unchanged`.** `spec_merge.rb`/`spec_apply.rb`/
  `spec_diff.rb` render only `applied`; the new no-op counts are not surfaced to
  the operator. Explicitly deferred by the brief (cosmetic follow-up), not a
  defect — `applied` rendering is unchanged so existing CLI output is stable.
- **`:unchanged` rides along on the merged spec model** returned by `apply`.
  It is inert for serialization (verified against `SpecDocument.serialize`
  reading only frontmatter/preamble/requirements/tail), so it round-trips
  harmlessly.
