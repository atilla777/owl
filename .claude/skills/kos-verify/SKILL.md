---
name: kos-verify
description: Run the smallest relevant checks for the active KOS task and return verification results.
---

# Skill: kos-verify

## Purpose

`kos-verify` is the workflow stage skill for running the smallest relevant checks for the active task and producing structured verification results for durable persistence.

Use it to confirm that implementation satisfies the task spec before review and git handoff.

## When To Use

Use this skill when the current task workflow status is `testing`, or when implementation has just completed and the orchestrator needs verification before review.

Do not use this skill to silently accept failed checks, make broad implementation changes, or decide whether risky failures are acceptable.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- When work uncovers a repeatable project-specific pitfall, API behavior, workflow gotcha, verification issue, or other lesson that would prevent future mistakes, treat it as durable knowledge rather than private memory.
- Classify these entries with taxonomy `kind: nuance` and select existing `scope` and `topic` tags from `kos-api.list_tags`; do not invent taxonomy tags or free-form "what I learned" labels.
- Stage skills should return durable nuance candidates to the orchestrator. The orchestrator persists them through `kos-api.check_knowledge_conflicts` followed by `create_knowledge_entry` or `update_knowledge_entry` when the knowledge is not already captured.

- Use the task spec and `development_plan` artifact to decide which checks are relevant.
- Follow loaded project testing strategy knowledge for coverage expectations.
- Prefer the smallest relevant test set first, then expand only when needed.
- Use the KOS knowledge context bundle to account for project testing rules and known verification nuances.
- Start from the orchestrator-provided work-package and context packet; do not claim tasks, select workflow stages, or make hidden KOS mutations while verifying.
- Return results to the orchestrator for a `verification_report` artifact write; do not secretly transition workflow state.

## Inputs

- task id, title, spec body, and current workflow status
- current `development_plan` artifact
- changed file list or implementation summary
- repository root path
- known verification commands from the plan
- required KOS knowledge context bundle for the verification stage

## Outputs

- commands or checks run
- pass/fail status for each check
- concise failure summary with relevant error lines or symptoms
- `verification_report` artifact body in Markdown, suitable for reload by later review or completion stages
- recommended next workflow status: `reviewing` after success or `implementing` after an obvious in-scope fix is needed
- unresolved failed-check decision when human judgment is required

## Workflow

1. Read the verification section of the `development_plan`.
2. Confirm the required KOS knowledge context bundle is present and has an acceptable status.
3. Select the smallest command or manual check that can validate the changed behavior.
4. Run the selected check from the repository root.
5. If it fails due to an obvious in-scope implementation issue, return failure details for `kos-implement` retry.
6. If the first check passes but the change is broad enough to need more coverage, run the next relevant check.
7. Return a structured verification summary and `verification_report` body to the orchestrator.

## Retry Behavior

Failed verification should normally route back to `kos-implement` when the fix is clear and inside scope. After the fix, the orchestrator should call `kos-verify` again with the prior failure details.

Stop for human judgment when the failure is unrelated, environment-specific, risky to ignore, or would require expanding task scope.

## Stop Conditions

Stop and return a clear blocker to the orchestrator when:

- required verification commands are unknown and cannot be inferred safely
- required KOS knowledge context is missing, blocked, failed to load, or not acceptable for verification
- checks fail for reasons that may be unrelated to the task
- the environment cannot run the relevant checks
- a failing check suggests a product or architecture decision rather than a straightforward bug
- verification would require destructive operations or modifying unrelated local state

## Persistence Responsibilities

This skill returns verification results and a `verification_report` body. The orchestrator persists it through `kos-api.write_task_artifact` with public artifact key `verification_report` before moving from `testing` to `reviewing`.

## Verification

Verify this skill by checking that:

- commands match the task scope and repository conventions
- failures include enough detail for the next implementation pass
- passed checks are named explicitly
- unverified areas are reported instead of implied as covered
- the artifact key remains `verification_report`
