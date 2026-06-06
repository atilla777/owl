---
status: approved
summary: Build a RequirementBlock-based spec parser + delta parser + deterministic DeltaMerger in Owl::Specs, exposed via owl spec apply/diff, re-validating the merged spec before writing; reuse P1's SpecLocator/validation and the section-scanning approach from P3.
---

# Context

P1 gives `Owl::Specs::Api` (`path/list/show/validate`) + `SpecLocator` over the `specs` storage
role, with domain slug-validation and descriptor-based validation reusing
`Validation::Internal::ArtifactRunner`. P3 gives `SectionScanner` (heading→segment splitter,
fence-aware) under `lib/owl/validation/internal/`. The spec body is a markdown doc with
`# Spec`, `## Purpose`, `## Requirements`, then `### Requirement: <name>` blocks each containing
`#### Scenario:` + WHEN/THEN. The merge unit is the `### Requirement: <name>` block.

# Decision

**1. Spec model — RequirementBlock parsing.** Add `lib/owl/specs/internal/spec_document.rb`
(`module_function`): parse a spec body into `{frontmatter, preamble, requirements: [{name,
heading, body}], tail}` where each requirement spans from its `### Requirement:` line to the next
`### ` or `## ` heading or EOF. `name` = trimmed text after `### Requirement:`. Provide
`serialize(model)` that reconstructs the body byte-stably (preamble + requirements in order +
tail). Reuse `SectionScanner` heading semantics (require it from validation/internal) rather than
re-implementing heading regex.

**2. Delta model.** Add `lib/owl/specs/internal/spec_delta.rb` (`module_function`): parse a delta
markdown into `{added: [block], modified: [block], removed: [name]}` by reading the three
`## ADDED|MODIFIED|REMOVED Requirements` sections; each block parsed with the same requirement
splitter. Validation: unknown `## X Requirements` heading → `invalid_delta`; a name appearing in
more than one section → `invalid_delta`; empty delta (no recognized sections / no operations) →
`invalid_delta`.

**3. Merge engine.** `lib/owl/specs/internal/delta_merger.rb` (`module_function`)
`apply(spec_model, delta) -> Result(model)`:
- Order: REMOVED, then MODIFIED, then ADDED (canonical; documented).
- REMOVED name not present → `delta_target_missing`. MODIFIED name not present →
  `delta_target_missing`; present → replace block (keep position). ADDED name already present
  (after removals/mods) → `delta_conflict`; else append in delta order under the Requirements
  section (before `tail`).
- Name match: exact, case-sensitive on trimmed title (documented).
- Returns the new model; serialization is deterministic ⇒ apply-twice-on-same-input is stable.

**4. Create-from-absent.** When the spec file is missing and the delta is ADDED-only, build a
minimal scaffold (frontmatter `status: draft`, `# Spec`, `## Purpose` placeholder,
`## Requirements`) then apply ADDED. MODIFIED/REMOVED against a missing spec → `spec_not_found`.

**5. Re-validate before write.** After producing the merged body, validate it against the `spec`
artifact type (reuse `Specs::Api.validate`'s descriptor path against an in-memory body — add a
`validate_body` helper that runs `ArtifactRunner`-style checks on a string, or write to a temp
path via storage and validate). If invalid → return the violations as `merge_would_invalidate`
and write NOTHING.

**6. Api + CLI.** `Owl::Specs::Api`:
- `diff(root:, domain:, delta_path:)` → `{ok, domain, before, after, unified_diff, valid,
  violations}` (no write).
- `apply(root:, domain:, delta_path:, dry_run: false)` → on success writes the spec via
  `Storage::Api.write` + `mkdir_p`; `dry_run: true` behaves like diff. Returns `{ok, domain,
  path, applied: {added, modified, removed counts}}`.
Read the delta file through `Storage::Api.read` (absolute path the caller passes; validate it
exists → `invalid_arguments`/`delta_not_found`). CLI commands `spec_apply.rb`, `spec_diff.rb`
under `cli/internal/commands/`, wired into `dispatch_spec` next to list/show/path/validate;
`--delta PATH` required, `--dry-run` flag on apply; update HELP_TEXT.

**7. Unified diff** computed in-process (simple line LCS or shell-free diff) for human preview;
keep it dependency-free.

# Alternatives

- **Free-form LLM merge (status quo)** — rejected: non-deterministic; the whole point of P4.
- **Treat scenarios as the merge unit** — rejected: requirements are the contract unit; OpenSpec
  deltas operate at requirement granularity; finer merging adds complexity without need now.
- **Register `spec_delta` as an artifact type** — deferred: deltas are transient inputs, not
  persisted task artifacts; the delta parser validates structure directly. Can be added later if
  deltas become first-class workflow artifacts (the merge_docs integration).
- **Rewire merge_docs now** — rejected (scope + would disrupt P5's own workflow run this session);
  documented as the follow-up that consumes this engine.
- **Shell out to `diff`** — rejected: keep deterministic + dependency-free + testable in-process.

# Risks

- **Block-boundary bugs** swallowing adjacent requirements/sections — mitigated by reusing
  SectionScanner semantics + targeted fixtures (adjacent requirements, trailing `## ` section,
  nested `####`). Highest-risk area; most tests focus here.
- **Serialization drift** (trailing newlines, spacing) breaking byte-stability/idempotence —
  mitigated by a canonical serializer + a determinism test (apply twice ⇒ identical) and a
  round-trip test (parse→serialize of an untouched spec is identity).
- **Partial writes** on error — mitigated: validate + merge fully in memory; only write on full
  success (atomic single `Storage::Api.write`).
- **Name collisions / whitespace in titles** — exact trimmed match, documented; tests cover
  trailing spaces and duplicate names.
- **api.rb coverage** — `lib/owl/specs/api.rb` is public → exercise every new branch (ok + each
  err) through the Api/CLI path.

# API

New public on `Owl::Specs::Api`: `diff(root:, domain:, delta_path:)`,
`apply(root:, domain:, delta_path:, dry_run: false)` → `Result`.
New internal: `Owl::Specs::Internal::{SpecDocument, SpecDelta, DeltaMerger}` + a small in-process
unified-diff helper.
New CLI: `owl spec apply <domain> --delta <path> [--dry-run]`, `owl spec diff <domain> --delta
<path>`. Errors: `invalid_delta`, `delta_conflict`, `delta_target_missing`, `spec_not_found`,
`merge_would_invalidate`, `delta_not_found`. JSON shapes per Decision §6. `lib/owl/specs/api.rb`
requires 100% line coverage.
