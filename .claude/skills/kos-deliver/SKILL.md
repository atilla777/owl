---
name: kos-deliver
description: Autonomously deliver a reviewed task by committing, pushing, and capturing the git trace when verification and review both pass.
---

# Skill: kos-deliver

## Purpose

`kos-deliver` is the autonomous delivery stage skill that ships a task once `verification_report` and `review_report` both report success.

Use it to coordinate scoped staging, commit, push, and git trace capture through `kos-repo`, without requiring a human approval gate. When a task is verification-only, review-only, documentation-only, or otherwise intentionally produces no scoped repository changes, use it to capture an `existing_head_no_changes` trace instead of forcing an empty commit.

This skill replaces the previous `kos-git-handoff` skill. The Rails service method `Tasks::Services::FinalizeTaskWorkflow#finalize_task_no_op_git_handoff` and the matching CLI command `bin/kos task:git-handoff:no-op` keep their existing names for backward compatibility; only the skill is renamed.

## When To Use

Use this skill when the current task workflow status is `delivering` on any workflow type that declares it (`Subtask workflow`, `Feature workflow`, `Bugfix workflow`). Container workflow does not declare a `delivering` stage and never dispatches here.

Do not use this skill to bypass failed verification, force-push, rewrite history, stage unrelated worktree changes, or run without a passing `review_report`.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- When work uncovers a repeatable project-specific pitfall, API behavior, workflow gotcha, verification issue, or other lesson that would prevent future mistakes, treat it as durable knowledge rather than private memory.
- Classify these entries with taxonomy `kind: nuance` and select existing `scope` and `topic` tags from `kos-api.list_tags`; do not invent taxonomy tags or free-form "what I learned" labels.
- Stage skills should return durable nuance candidates to the orchestrator. The orchestrator persists them through `kos-api.check_knowledge_conflicts` followed by `create_knowledge_entry` or `update_knowledge_entry` when the knowledge is not already captured.

- Follow `skills/kos-repo/SKILL.md` for repository safety operations.
- Follow loaded project knowledge and repository delivery policy for commit and push rules.
- Use the task spec, development plan, verification report, documentation update (when the workflow declares a documenting stage), and review report to determine commit scope.
- Do not require a KOS knowledge context bundle for delivery; commit and push safety rules live in this skill and `kos-repo`.
- Start from the orchestrator-provided delivery packet; do not claim tasks, select workflow stages, or make hidden KOS mutations during repository delivery.
- Return git trace output to the orchestrator; do not secretly finalize KOS task state.

## Inputs

- task id, title, and intended commit scope
- repository root path
- persisted `verification_report` artifact (required; pass=true)
- persisted `review_report` artifact (required; outcome=ready for delivering, no required fixes)
- persisted `documentation_update` artifact (required when the workflow declares a `documenting` stage)
- expected changed files, when known
- current branch and remote expectations, when known
- optional KOS knowledge context bundle when project-specific delivery constraints already exist

## Outputs

- repository status summary before delivery
- pre-flight verification + review pass/fail decision
- suspicious or unrelated change findings, if any
- committed message when commit succeeds
- push result when push succeeds
- git trace payload with branch, commit SHA, commit message, and observed timestamp
- delivery mode: `new_commit` when a task commit is created, or `existing_head_no_changes` when no scoped changes exist and current `HEAD` is the correct delivery trace
- recommended next workflow status: `done` after successful delivery (the orchestrator then writes the `completion_report` and transitions to `done`)
- explicit stop reason when delivery cannot continue safely

## Workflow

1. **Pre-flight verify + review pass.** Read the persisted `verification_report` and `review_report` artifacts from the work package. Confirm:
   - `verification_report` frontmatter `status` is approved and the report's outcome is pass (no failing checks pending human judgment).
   - `review_report` frontmatter `status` is approved, the outcome line is "Ready for delivering" (or equivalent positive outcome), and the `## Findings` section contains no entries marked as required fixes.
   - For workflows that declare a `documenting` stage, a `documentation_update` artifact exists and its frontmatter `status` is approved. (The Documentation Rationale Check is run by `kos-review`; this skill only confirms the artifact exists and is approved.)
   If any pre-flight check fails, stop and return a blocker pointing at the specific artifact and field — do not commit, do not push, do not transition.
2. Inspect `git status --short`, unstaged diff, staged diff, recent commit style, and current branch through `kos-repo`.
3. Treat missing or empty KOS knowledge context as acceptable for delivery; use project knowledge only when it is already loaded and relevant.
4. Screen for suspicious files and unrelated changes.
5. If there are no staged or unstaged scoped changes, and verification/review/documentation_update confirm the task intentionally required no repository edits, return success with delivery mode `existing_head_no_changes`. Capture the current branch, `HEAD` commit SHA, `HEAD` commit message, and observed timestamp for KOS git trace persistence. Do not create an empty commit and do not stage unrelated runtime files.
6. Stage only files scoped to the active task when scoped changes exist.
7. Reinspect staged diff to confirm it matches the task scope.
8. Commit with a concise message matching repository style.
9. Before pushing, determine whether the current branch is a default branch such as `main`, `master`, or `trunk`. Direct pushes to default branches require explicit safe policy from the work package, project configuration, or human intent; otherwise stop and use a non-default branch or PR path.
10. Push to the existing safe upstream, or use upstream tracking only when remote and branch are clear and default-branch policy permits the push.
11. Capture branch, commit SHA, commit message, and observed timestamp for KOS git trace persistence with delivery mode `new_commit`.
12. Return the git trace payload and recommended next workflow status `done` to the orchestrator. The orchestrator persists the trace through `finalize_task_git_trace`, writes the `completion_report`, and transitions to `done` autonomously — no human approval gate.

## Autonomous Delivery Policy

This skill is intentionally autonomous: when the pre-flight check passes and the repository state is safe, it commits, pushes, and hands the workflow forward without stopping for human approval. The previous `awaiting_git_approval` gate has been removed from the workflow.

Autonomy is bounded by the stop conditions below. The skill will refuse to deliver — and route control back to the human — whenever any pre-flight check fails, any repository-safety check fails, or the verification/review evidence is incomplete.

## Stop Conditions

Stop and return a clear blocker to the orchestrator when:

- the persisted `verification_report` is missing, has frontmatter `status` other than approved, or reports a failed check that needs judgment
- the persisted `review_report` is missing, has frontmatter `status` other than approved, contains required fixes in `## Findings`, or its outcome line does not say the task is ready for delivering
- the workflow declares a `documenting` stage but the `documentation_update` artifact is missing or its frontmatter `status` is not approved
- suspicious files may be included in the commit
- unrelated staged or unstaged changes make commit scope ambiguous
- there are no scoped changes, but the task is not clearly verification-only/review-only/documentation-only or the supporting artifacts do not explicitly support a no-change delivery
- branch, remote, upstream, authentication, or repository policy is unclear
- the current branch is a default branch such as `main`, `master`, or `trunk` and no explicit safe policy from the work package, project configuration, or human intent permits a direct push
- hooks fail and the fix is not obvious and in scope
- the delivery would require force-push, amend, reset, checkout, or any destructive git operation

## Persistence Responsibilities

This skill performs repository delivery and returns a git trace payload. The orchestrator persists the trace through `kos-api.finalize_task_git_trace`, writes the `completion_report`, and transitions workflow state to `done`. This skill must not call `finalize_task_git_trace` or `transition_task_workflow` directly.

## Verification

Verify this skill by checking that:

- delivery only proceeds when `verification_report` and `review_report` are both approved (and `documentation_update` is approved when the workflow declares a documenting stage)
- only task-scoped files are staged
- verification-only/review-only/documentation-only tasks with no scoped diff return `existing_head_no_changes` and current `HEAD` trace without creating an empty commit
- suspicious files stop the delivery before commit
- default-branch pushes stop unless explicit safe policy from the work package, project configuration, or human intent permits direct push; otherwise use a branch or PR path
- commit and push both succeed before returning a successful trace
- the trace fields match `kos-api` git trace operation expectations
- the skill does not call `finalize_task_git_trace` or `transition_task_workflow` itself; the orchestrator owns those persistence calls
