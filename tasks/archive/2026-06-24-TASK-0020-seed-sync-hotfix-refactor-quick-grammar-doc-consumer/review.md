---
status: resolved
summary: "Seed-sync of hotfix/refactor/quick + self-contained Requirement/Scenario grammar is correct and complete; all 5 workflows ship with resolvable sources, no root↔.owl drift, version bumped 0.8.0 with CHANGELOG. Approved with out-of-scope follow-ups."
verdict: accepted_with_followups
ready: true
---

# Summary

Self-review of the `implement` diff for TASK-0020 (promote `hotfix`/`refactor`/`quick`
workflow seeds + Requirement/Scenario grammar into the gem distribution). The change
makes a fresh `owl init`/`owl upgrade` deliver all 5 workflows and a working,
self-contained grammar reference, eliminating the dogfood-vs-gem divergence.

Verdict: **accepted_with_followups**. Every acceptance criterion in the brief is met,
all objective checks pass (see `verification.md`), and no real defect was found. The
follow-ups listed below are all explicitly out of scope for this task.

# Findings

Reviewed against the brief acceptance criteria and the step's review focus. All
load-bearing checks passed:

1. **Root workflow seeds present & drift-free.** `workflows/hotfix/`,
   `workflows/refactor/`, `workflows/quick/` now exist with `workflow.yaml` + all
   context files. `diff -rq` against the `.owl/workflows/` copies reports **zero**
   differences for all 5 workflows. Every `context_file:` reference in the three new
   `workflow.yaml`s resolves to a present file (23 refs checked, all OK).

2. **Default registry consistent.** `lib/owl/workflows/internal/default_template.rb`
   `render` heredoc now lists all 5 workflows. `hotfix`/`refactor`/`quick` are
   `managed: true`, `enabled: true`, `version: "1.0"`, titled, with
   `source: workflows/<id>/workflow.yaml` — and all 5 source paths exist on disk.
   `owl workflow list --json` returns 5 entries, each `source_present: true`;
   `owl workflow validate hotfix|refactor|quick` all return `valid: true`.

3. **Grammar self-contained.** A compact "Requirement/Scenario grammar" section
   (RFC-2119 `### Requirement:` + `#### Scenario:` with UPPERCASE `- WHEN`/`- THEN`/
   `- AND`) is embedded in every seeded brief context across all 5 workflows. The dead
   `docs/agents/31_...` reference in `artifacts/brief/artifact.yaml`
   (`required_patterns` description) and `artifacts/brief/templates/default.md` is
   repointed to the inline section. Root `artifacts/brief/*` and `.owl/artifacts/brief/*`
   are byte-identical (`diff` exit 0). No `31_...` reference remains in any brief
   artifact or seeded brief context.

4. **Versioning.** `Owl::VERSION` 0.7.2 → 0.8.0 (minor — new consumer-facing seed
   content, correct SemVer). `CHANGELOG.md` has a well-formed `## [0.8.0] - 2026-06-24`
   entry with two `### Added` items describing both changes accurately.

5. **New cross-check spec.** `spec/owl/workflows/default_template_sources_spec.rb`
   asserts the registry lists exactly the 5 workflows, every entry is managed/enabled/
   v1.0/titled, every `source:` equals `workflows/<key>/workflow.yaml` and exists on
   disk, and a materialized `.owl/workflows/<key>/workflow.yaml` is present among
   `SeededSources.files`. 4 examples, 0 failures.

6. **Coverage invariant intact.** Only `lib` files touched are `default_template.rb`
   (internal, exercised by the new spec) and `version.rb`. No `lib/owl/**/api.rb`
   touched — the 100% api-coverage rule is unaffected, as the implement report claimed.

# Resolution

No findings require code changes. All acceptance criteria are satisfied and all
verification checks are green (1787 examples / 0 failures; rubocop net-zero new
offenses; 5-workflow smoke checks pass). The step is approved.

# Remediation

None required for this task. The items under "Residual risks" are tracked as
out-of-scope follow-ups, not remediation of this diff.

# Residual risks

All out of scope for TASK-0020 (do not block this delivery):

- **Dead `31_...` link survives in `spec`/`spec_delta` artifacts.** Same dead-link
  class as the brief had, but those artifact types were out of this (brief-focused)
  task's scope. Three references remain in `artifacts/spec/templates/default.md`,
  `artifacts/spec_delta/artifact.yaml`, `artifacts/spec_delta/templates/default.md`
  (mirrored in `.owl/`). Worth a follow-up if those artifacts are intended for
  consumers.
- **Dogfood `.owl/workflows.yaml` `quick` entry still `managed: false`** and
  `.owl/config.yaml` version still 0.7.2 — reconciled via `owl upgrade` after gem
  rebuild, per project propagation convention. Not hand-editable here.
- **Untracked `tasks/TASK-0021..0024/` and modified `tasks/index.yaml`** are backlog
  scaffolding for separate queued tasks, present in the working tree but NOT part of
  this code change. The later `commit_push`/`archive` steps MUST NOT sweep
  TASK-0021..0024 into TASK-0020's commit. (Tooling note, not a code review finding.)
