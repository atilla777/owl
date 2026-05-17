---
name: kos-implement
description: Make scoped repository changes from an approved or current KOS development plan.
---

# Skill: kos-implement

## Purpose

`kos-implement` is the workflow stage skill for making scoped repository changes from an approved or current `development_plan` artifact.

Use it to implement the smallest correct change for the active task while preserving unrelated worktree changes and leaving workflow transitions to the orchestrator.

## When To Use

Use this skill when the current task workflow status is `implementing` and the work package contains a clear task spec and development plan.

Do not use this skill to broaden task scope, approve failed checks, perform git handoff, or create unrelated cleanup changes.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- When work uncovers a repeatable project-specific pitfall, API behavior, workflow gotcha, verification issue, or other lesson that would prevent future mistakes, treat it as durable knowledge rather than private memory.
- Classify these entries with taxonomy `kind: nuance` and select existing `scope` and `topic` tags from `kos-api.list_tags`; do not invent taxonomy tags or free-form "what I learned" labels.
- Stage skills should return durable nuance candidates to the orchestrator. The orchestrator persists them through `kos-api.check_knowledge_conflicts` followed by `create_knowledge_entry` or `update_knowledge_entry` when the knowledge is not already captured.

- Treat the loaded task work package and `development_plan` artifact as authoritative for implementation scope.
- Follow loaded project knowledge, relevant repository rules, and existing code conventions.
- Treat the KOS knowledge context bundle as required project context before code edits; repository docs are supporting fallback context only.
- Preserve unrelated user or agent changes in the worktree.
- Use `kos-api` only through the orchestrator for durable task updates or knowledge capture.
- Start from the orchestrator-provided work-package and context packet; do not claim tasks, select workflow stages, or make hidden KOS mutations while implementing.
- Return implementation results to the orchestrator; do not secretly transition workflow state.

## Inputs

- task id, title, spec body, and current workflow status
- current `development_plan` artifact
- relevant workflow blockers and artifact requirements
- repository root path
- optional verification or review feedback from a previous failed pass
- required KOS knowledge context bundle for the implementation stage

## Outputs

- list of changed files scoped to the task
- implementation summary focused on behavior or capability delivered
- any tests added or updated
- discovered blockers, scope expansions, or durable nuance knowledge candidates
- recommended next workflow status, usually `testing` when implementation is complete

## Workflow

1. Re-read the task spec and current `development_plan`.
2. Confirm the required KOS knowledge context bundle is present and has an acceptable status.
3. Inspect only the files needed for the planned change.
4. Check the worktree before edits when there is a risk of touching files with unrelated changes.
5. Make the smallest code, test, or documentation changes needed to satisfy the plan.
6. Keep responsibilities local and avoid speculative abstractions.
7. If prior verification or review feedback exists, address only the relevant failure or finding.
8. Include durable nuance knowledge candidates when the implementation exposes a repeatable mistake, API behavior, workflow gotcha, or verification lesson useful for future tasks.
9. Return changed files, summary, and recommended next status to the orchestrator.

## Retry Behavior

When verification or review fails and the next fix is within the existing task scope, the orchestrator may call this skill again with the failure details. The skill should make a targeted fix and return to verification.

Do not absorb new product scope or prerequisites during retry. Return a blocker when the fix would change the agreed task boundary.

## Stop Conditions

Stop and return a clear blocker to the orchestrator when:

- the development plan is missing or too vague to implement safely
- required KOS knowledge context is missing, blocked, failed to load, or not acceptable for implementation
- implementation requires a prerequisite or scope expansion not covered by the current plan
- existing worktree changes conflict with the files that must be edited
- suspicious files, generated artifacts, or local data would need to be modified without clear source-of-truth rules
- the codebase structure contradicts the planned approach enough that the plan must be revised

## Persistence Responsibilities

This skill edits repository files only. The orchestrator persists workflow state, artifacts, blockers, or durable nuance knowledge through `kos-api` when needed.

## Verification

Verify this skill by checking that:

- every changed file is tied to the task plan
- tests or docs are updated when the changed behavior requires them
- no unrelated worktree changes are reverted or staged
- any blocker is reported before changing scope
