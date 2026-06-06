---
status: approved
summary: Add a deterministic structural delta-merge engine that applies ADDED/MODIFIED/REMOVED Requirement deltas into a living spec, exposed via owl spec apply/diff, replacing free-form LLM re-writing of the source of truth.
---

# Problem

Today the `merge_docs` step does free-form, LLM-driven re-writing of prose docs, and for the
`feature` workflow `owl publish` returns `no_publishable_step` — so updating the source of truth
is non-deterministic and, in practice, manual. The Owl-vs-OpenSpec comparison (Problem 4) calls
for a **structural delta**: changes expressed as `## ADDED / ## MODIFIED / ## REMOVED
Requirements` and merged into the living spec (P1's `specs/<domain>/spec.md`) by deterministic
rules, so the same delta always yields the same result.

P1 shipped the persistent `spec` artifact + `Owl::Specs::Api`; P2 made the Requirement/Scenario
grammar the standard. What is missing is the **merge mechanism** that takes a delta and applies
it to a spec reproducibly.

# Goal

Deliver a deterministic delta-merge engine + CLI:

- A delta format: a markdown doc with `## ADDED Requirements`, `## MODIFIED Requirements`,
  `## REMOVED Requirements`, each holding `### Requirement:` blocks (full grammar for
  ADDED/MODIFIED; name — optionally with reason — for REMOVED).
- An engine that parses the spec into Requirement blocks (keyed by the `### Requirement: <name>`
  title) and applies the delta: ADDED appends, MODIFIED replaces by name, REMOVED deletes by
  name — same delta + same spec ⇒ identical output (byte-stable serialization).
- CLI: `owl spec apply <domain> --delta <path> [--dry-run]` and `owl spec diff <domain> --delta
  <path>` (preview without writing).
- The merged spec must still validate against the `spec` artifact type.

Out of scope (explicit): rewiring the `feature` workflow's `merge_docs` step to auto-produce and
apply deltas — that changes every task's flow and is a separate, deliberate workflow change. This
task ships the reusable engine + CLI; the brief/design records the integration path.

# Scenarios

### Requirement: ADDED requirements are appended

The engine SHALL append each `### Requirement:` under `## ADDED Requirements` into the spec's
Requirements section.

#### Scenario: Add a new requirement
- WHEN a delta's `## ADDED Requirements` contains `### Requirement: X` (with a scenario) and the
  spec has no requirement named `X`
- THEN after `owl spec apply` the spec contains requirement `X` with its scenario
- AND re-serializing is byte-identical to a second identical apply onto the same input

#### Scenario: Add a conflicting requirement
- WHEN ADDED contains a requirement whose name already exists in the spec
- THEN apply fails with a structured `delta_conflict` error and writes nothing

### Requirement: MODIFIED requirements replace by name

The engine SHALL replace an existing requirement block with the delta's version, matched by
requirement name.

#### Scenario: Modify an existing requirement
- WHEN `## MODIFIED Requirements` contains `### Requirement: X` and the spec has requirement `X`
- THEN the spec's `X` block is replaced by the delta's `X` block
- AND a requirement named in MODIFIED but absent from the spec fails with `delta_target_missing`

### Requirement: REMOVED requirements are deleted

The engine SHALL delete a named requirement from the spec.

#### Scenario: Remove a requirement
- WHEN `## REMOVED Requirements` names `### Requirement: X` present in the spec
- THEN the spec no longer contains requirement `X`
- AND removing a non-existent requirement fails with `delta_target_missing`

### Requirement: Apply is deterministic and previewable

The engine SHALL produce a stable result and support a no-write preview.

#### Scenario: Dry run writes nothing
- WHEN `owl spec apply <domain> --delta d.md --dry-run` (or `owl spec diff`) is run
- THEN the resulting spec body / unified diff is printed and the file on disk is unchanged

#### Scenario: Merged spec stays valid
- WHEN a delta is applied
- THEN the resulting spec passes `owl spec validate <domain>` (grammar intact); if the merge
  would produce an invalid spec, apply fails with the validation violations and writes nothing

# Edge cases

- Spec does not yet exist + delta is ADDED-only → create the spec from a minimal scaffold
  (Purpose placeholder + the added requirements); MODIFIED/REMOVED against a missing spec →
  `spec_not_found`.
- Requirement name matching: exact match on the trimmed title text after `### Requirement:`;
  decide case sensitivity (default exact/case-sensitive) and document it.
- Requirement block boundaries: a block spans to the next `### ` or `## ` heading or EOF (must not
  swallow the next requirement or the trailing section).
- Empty delta or a delta with an unknown `## X Requirements` section → structured
  `invalid_delta` error.
- Ordering: ADDED appended in delta order; output serialization canonical and idempotent for a
  re-run on the same inputs.
- Domain slug validation + traversal guard reused from P1.
- A delta touching the same requirement in two sections (e.g. MODIFIED + REMOVED) → `invalid_delta`.

# Acceptance criteria

- [ ] Delta parser + spec parser + merge engine implemented (deterministic, byte-stable output).
- [ ] `owl spec apply <domain> --delta <path> [--dry-run]` and `owl spec diff <domain> --delta
      <path>` implemented (JSON-first; apply writes spec, dry-run/diff do not).
- [ ] ADDED/MODIFIED/REMOVED semantics + structured errors (`delta_conflict`,
      `delta_target_missing`, `invalid_delta`, `spec_not_found`).
- [ ] Merged spec re-validated against the `spec` type; invalid result aborts the write.
- [ ] Engine logic in `Owl::Specs` (public api.rb → 100% line coverage) via storage roles, no
      hard-coded paths, no raw File/Dir.
- [ ] RSpec coverage for each operation, conflict/missing/invalid-delta, dry-run no-write,
      determinism (apply twice ⇒ same), and create-from-absent.
- [ ] `bundle exec rspec` green for touched areas; `bundle exec rubocop` clean (never `-A`).
