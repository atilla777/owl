---
status: approved
summary: "Extend the optional spec_delta merge wiring (delivered for feature in TASK-0007) to the hotfix and refactor workflows, and apply two cosmetic polish items: a surgical flip_delta_status edit and a clarified merge_task doc comment about gate-fail status flipping."
---

# Problem

TASK-0007 wired the spec layer into the `feature` workflow: an optional `spec_delta` artifact and
a `merge_docs` step that runs `owl publish` AND `owl spec merge`. The `hotfix` and `refactor`
workflows have the identical step structure (including a `merge_docs` step with its own context)
but were NOT wired, so a hotfix/refactor that changes a domain's behaviour cannot record it in the
living spec through its own workflow. Two cosmetic items from the TASK-0008 review also remain:
`flip_delta_status` re-dumps the whole front matter (can reformat unrelated keys) and the
`merge_task` doc comment does not mention that the delta `status` flips to `merged` even on a
gate-fail.

# Goal

Bring `hotfix` and `refactor` to parity with `feature` for the spec layer, and apply the two
low-risk polish items — all backward-compatible (tasks with no `spec_delta` are unaffected).

# Scenarios

### Requirement: hotfix and refactor declare the optional spec_delta artifact

The system SHALL declare `spec_delta` as an optional artifact in the hotfix and refactor workflows,
mirroring feature, without adding a creating step.

#### Scenario: workflow validates with the optional artifact
- WHEN `spec_delta` is added to the hotfix and refactor `artifacts:` maps (storage role tasks,
  path `{{task.id}}/spec_delta.md`) with no step creating it
- THEN `owl workflow validate hotfix` and `owl workflow validate refactor` both return `valid:true`
- AND the step graph of each workflow is unchanged
- TEST: spec/owl/workflows/hotfix_refactor_spec_delta_spec.rb (validate example)

### Requirement: hotfix and refactor merge_docs runs spec merge

The system SHALL update the hotfix and refactor `merge_docs` context to run `owl spec merge`
alongside `owl publish`, a no-op when no spec_delta is present.

#### Scenario: spec-less hotfix/refactor merge_docs is a no-op
- WHEN a hotfix or refactor task with no `spec_delta` reaches merge_docs and the step runs
  `owl spec merge TASK-ID`
- THEN it returns `{ok:true, applied:false, reason:"no_spec_delta"}` and writes nothing
- TEST: spec/owl/integration/hotfix_refactor_merge_docs_spec.rb (no-op example)

### Requirement: flip_delta_status edits only the status line

The system SHALL update the spec_delta `status` with a surgical front-matter edit that leaves other
front-matter keys and formatting unchanged.

#### Scenario: Unrelated front-matter keys preserved on flip
- WHEN a successful non-dry-run `owl spec merge` flips a delta whose front matter has extra keys
  and specific quoting/indentation
- THEN only the `status:` value changes; other keys and their formatting are byte-preserved
- TEST: spec/owl/specs/merge_task_idempotency_spec.rb (surgical-flip example)

# Edge cases

- Active `.owl/` and seed `artifacts/`/`workflows/` copies must stay in sync (seed-parity suite).
- `flip_delta_status` must still handle a front matter without an explicit `status:` line (append
  it) and re-validate against the `spec_delta` type.
- hotfix/refactor were scaffolded from feature and are "tailor before serious use" — wiring the
  optional artifact must not change their default no-spec behaviour.
- The doc-comment change is non-functional; no behaviour change.

# Acceptance criteria

- [ ] `spec_delta` declared optional in hotfix + refactor workflow.yaml (active + seed); both
      `owl workflow validate` pass; step graphs unchanged.
- [ ] hotfix + refactor `merge_docs.context.md` (active + seed) updated to run `owl spec merge`
      with the same no-op semantics documented for feature.
- [ ] `flip_delta_status` rewrites only the `status:` line (surgical), preserving other front-matter
      keys/formatting; falls back to appending `status:` when absent.
- [ ] `merge_task` doc comment notes the status flips to `merged` even on a gate-fail.
- [ ] RSpec: hotfix/refactor workflow validate + spec-less merge_docs no-op; surgical-flip
      preservation; existing TASK-0007/0008 specs stay green.
- [ ] `bundle exec rspec` green for touched areas; `bundle exec rubocop` clean (never `-A`).
