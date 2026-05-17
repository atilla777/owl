---
name: kos-review
description: Review the completed task diff for correctness, regressions, missing tests, and complexity.
---

# Skill: kos-review

## Purpose

`kos-review` is the workflow stage skill for reviewing the completed task diff for correctness, regressions, missing tests, and unnecessary complexity.

Use it to produce or update a `review_report` artifact before repository handoff.

## When To Use

Use this skill when the current task workflow status is `reviewing`, or after verification succeeds and the workflow supports a review report artifact.

Do not use this skill to make git commits, approve scope expansion, or hide findings that require another implementation pass.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- When work uncovers a repeatable project-specific pitfall, API behavior, workflow gotcha, verification issue, or other lesson that would prevent future mistakes, treat it as durable knowledge rather than private memory.
- Classify these entries with taxonomy `kind: nuance` and select existing `scope` and `topic` tags from `kos-api.list_tags`; do not invent taxonomy tags or free-form "what I learned" labels.
- Stage skills should return durable nuance candidates to the orchestrator. The orchestrator persists them through `kos-api.check_knowledge_conflicts` followed by `create_knowledge_entry` or `update_knowledge_entry` when the knowledge is not already captured.

- Review against the task spec, `development_plan`, persisted `verification_report`, and actual repository diff.
- Follow repository rules for architecture, testing, and workflow safety.
- Use the KOS knowledge context bundle as required project context for review expectations, known risks, and durable rules.
- Treat findings as primary output; summaries are secondary.
- Start from the orchestrator-provided work-package and context packet; do not claim tasks, select workflow stages, or make hidden KOS mutations while reviewing.
- Return review output to the orchestrator; do not secretly transition workflow state.

## Inputs

- task id, title, spec body, and current workflow status
- current `development_plan` artifact
- current `verification_report` artifact, when present
- current `documentation_update` artifact (required input for any task on a workflow type that declares the `documenting` stage — `Subtask workflow`, `Feature workflow`, `Bugfix workflow`)
- repository status and diff from `kos-repo` or direct inspection
- existing `review_report` artifact, when present
- required KOS knowledge context bundle for the review stage

## Outputs

- `review_report` artifact body in Markdown
- findings ordered by severity with file and line references when available
- missing-test or residual-risk notes
- required fixes that should route back to `kos-implement`
- recommended next workflow status, usually `delivering` when no required fixes remain

## Review Report Shape

Use this structure unless the workflow defines a different one:

```markdown
# Review Report

## Findings

- <Severity>: <file:line> <issue and impact>

## Verification Reviewed

- <Check or result considered>

## Documentation Reviewed

- <documentation_update artifact summary, plus per-skipped-doc rationale check>

## Residual Risks

- <Risk or testing gap, or "None identified">

## Outcome

<Ready for delivering, or requires implementation retry.>
```

If no findings are discovered, say so explicitly and still list residual risks or testing gaps.

## Documentation Rationale Check

For any task on a workflow type that declares the `documenting` stage (`Subtask workflow`, `Feature workflow`, `Bugfix workflow`), review MUST verify the persisted `documentation_update` artifact before recommending `delivering`. The check is mechanical and verifiable:

1. Confirm the artifact key `documentation_update` is present in the work package.
2. Confirm the body contains the literal required sections `## Updated docs`, `## Skipped docs (with rationale)`, and `## Verification` (byte-for-byte; `Tasks::AgentArtifacts::TemplateValidator` enforces this on the write side, but the review independently confirms it survived any human edit).
3. For each entry under `## Skipped docs (with rationale)`, confirm there is a concrete one-line rationale. Empty bullets, "TBD", "n/a", or "no docs touched" without explanation are review findings of severity at least `major` — route back to `kos-implement` (or, when scope is doc-only, back to `kos-document` via the orchestrator) for repair.
4. Cross-check the `## Updated docs` entries against the actual diff: every listed path must appear in the implementation diff or be a `LiveSkills::Skill` record id; conversely, doc files (`*.md`) modified by the diff that are not listed must appear under `## Skipped docs (with rationale)` with an explicit rationale.
5. Record the outcome in the `## Documentation Reviewed` section of the review report. If any rationale is missing or any documented path is fabricated, treat it as a required fix rather than a residual risk.

For Container workflow tasks (no documenting stage), skip this section entirely and note that the workflow does not declare a documenting stage.

## Workflow

1. Inspect repository status and diff for task-scoped changes.
2. Confirm the required KOS knowledge context bundle is present and has an acceptable status.
3. Compare the diff against the task spec, development plan, and persisted verification report.
4. For workflow types that declare a `documenting` stage, run the Documentation Rationale Check above and include its findings in the review report.
5. Check for behavioral regressions, missing tests, risky coupling, and unnecessary complexity.
6. Produce a review report with findings first.
7. Return required fixes to the orchestrator when another implementation or documentation pass is needed.
8. Recommend transition to `delivering` only when there are no required fixes or unresolved review decisions; the autonomous `kos-deliver` stage will then commit, push, and complete the task without further human approval when verification and review both pass.

## Retry Behavior

When review finds required code fixes within scope, the orchestrator should call `kos-implement` with the findings, then run verification and review again. When review finds documentation-only required fixes (missing rationale, fabricated doc path, missing required section), the orchestrator should route back to `kos-document` via a `documenting` retransition. The review report should preserve the final outcome rather than pretending the first pass succeeded.

## Stop Conditions

Stop and return a clear blocker to the orchestrator when:

- the diff includes unrelated or suspicious changes that make review scope ambiguous
- required KOS knowledge context is missing, blocked, failed to load, or not acceptable for review
- review finds a required fix outside the approved task scope
- the required verification report is missing, verification was skipped, or verification failed and the risk requires human judgment
- repository state changes during review in a way that invalidates the inspected diff

## Persistence Responsibilities

This skill produces the `review_report` body and recommended next status. The orchestrator persists the artifact through `kos-api` and applies workflow transitions with the latest lock version.

## Verification

Verify this skill by checking that:

- findings include concrete file and line references when possible
- no-finding reports explicitly say no findings were discovered
- required fixes are clearly separated from residual risks
- the artifact key remains `review_report`
- on workflows that declare a `documenting` stage, the review report contains a `## Documentation Reviewed` section and the Documentation Rationale Check has been applied to the persisted `documentation_update` artifact
- the recommended next status is `delivering` (not the legacy `awaiting_git_approval`) when no required fixes remain
