---
name: kos-repo
description: Safely inspect, review, commit, push, and capture git trace during KOS task delivery.
---

# Skill: kos-repo

## Purpose

`kos-repo` is the shared technical skill for safe repository inspection, review, commit, push, and git-trace capture during KOS task delivery flows.

Use it to keep the orchestrator focused on workflow-state decisions and git-handoff stage skills focused on delivery scope instead of rebuilding git safety rules, dirty-worktree checks, suspicious-file screening, commit conventions, and final trace output.

## When To Use

Use this skill when another KOS-owned skill needs to:

- inspect repository status before implementation, review, or handoff
- collect staged and unstaged diffs for self-review
- identify untracked files that may need staging or human review
- check recent commit messages before drafting a commit message
- stage scoped task changes without disturbing unrelated user changes
- create a commit for completed task work
- push the current branch after a successful commit
- capture branch, commit SHA, commit message, and observed timestamp for KOS git-trace persistence

Do not use this skill to decide product scope, implementation plans, task workflow transitions, or whether failed checks are acceptable. Workflow-state decisions belong to the orchestrator; stage-specific repository judgments belong to the calling stage skill.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- When work uncovers a repeatable project-specific pitfall, API behavior, workflow gotcha, verification issue, or other lesson that would prevent future mistakes, treat it as durable knowledge rather than private memory.
- Classify these entries with taxonomy `kind: nuance` and select existing `scope` and `topic` tags from `kos-api.list_tags`; do not invent taxonomy tags or free-form "what I learned" labels.
- Stage skills should return durable nuance candidates to the orchestrator. The orchestrator persists them through `kos-api.check_knowledge_conflicts` followed by `create_knowledge_entry` or `update_knowledge_entry` when the knowledge is not already captured.

- Follow loaded project knowledge, repository handoff policy, and the active task spec before applying repository operations.
- Treat KOS application state as authoritative for task workflow state and persisted git trace.
- Keep this skill in `skills/kos-repo/` while it is experimental. Do not move it into `.opencode/skills` until the application skill workflow has been proven end to end.
- Never rely on hidden local files or private skill state to resume repository work.

## Inputs

- repository root path
- active task id and title
- intended commit scope
- optional list of files the caller expects to include
- latest verification result summary
- remote and branch expectations, when the caller has them

## Outputs

- repository status summary
- relevant staged and unstaged diff summary
- suspicious-file findings, if any
- commit message draft or committed message
- push result summary
- git trace payload with branch, commit SHA, commit message, and observed timestamp
- explicit stop reason when repository handoff cannot continue safely

## Safe Inspection Operations

Before review or git handoff, collect:

- `git status --short` to see modified, staged, and untracked files
- `git diff` for unstaged changes
- `git diff --staged` for staged changes
- `git log --oneline -5` to match repository commit message style
- `git branch --show-current` to capture the active branch
- `git remote -v` only when push destination needs confirmation

Before pushing, identify whether the current branch is a default branch such as `main`, `master`, or `trunk`. Do not treat an existing upstream on a default branch as sufficient approval for direct push.

Inspect both staged and unstaged changes before committing. Do not assume the staging area contains only the current task.

## Suspicious File Screening

Stop and return control to the caller when the change set includes files that may contain secrets or machine-local state, such as:

- `.env` or `.env.*`
- credential files, private keys, tokens, or certificates
- database dumps or local SQLite data files
- editor, OS, or cache files not already tracked intentionally
- generated files whose source of truth is unclear

When suspicious files are present, report the exact paths and ask the orchestrator or human to decide whether they should be excluded, committed, or investigated.

## Staging Rules

Stage only files that belong to the active task's intended scope. Preserve unrelated user changes even when they are present in the worktree.

Prefer explicit path staging:

```bash
git add path/to/file another/path
```

Avoid broad staging commands such as `git add .` unless the inspected change set is small, clearly scoped, and contains no unrelated or suspicious files.

## Commit Rules

Create a commit only after implementation, verification, and review are complete, or when the orchestrator explicitly asks for a repository handoff.

Before committing:

1. Confirm there are staged changes.
2. Confirm the staged diff matches the active task scope.
3. Confirm suspicious-file screening found no unresolved concerns.
4. Draft a concise message that matches recent repository style and describes the completed outcome.

Do not amend commits unless the human explicitly requests it and the repository safety rules allow it.

Do not rewrite history, force-push, hard-reset, or discard changes through this skill.

## Push Rules

Push after a successful task-completion commit when there are no unresolved questions, failed checks requiring a decision, suspicious files, ambiguous commit scope, default-branch policy concerns, or push-destination concerns.

Direct pushes to default branches such as `main`, `master`, or `trunk` require explicit safe policy from the work package, project configuration, or human intent. If that policy is absent or unclear, stop before pushing and return control to the caller so the task can use a non-default branch or PR path.

If the branch has no upstream, push with upstream tracking only when the branch name and remote destination are clear:

```bash
git push -u origin current-branch-name
```

Otherwise use the existing upstream:

```bash
git push
```

Stop before pushing when the current branch, remote, authentication, or repository policy is unclear.

## Git Trace Payload

After a successful commit, capture a trace payload that can be persisted through `kos-api`:

```json
{
  "git_branch": "main",
  "git_commit_sha": "<sha>",
  "git_commit_message": "<message>",
  "git_commit_observed_at": "<iso8601 timestamp>"
}
```

Use `git rev-parse HEAD` for the SHA, `git log -1 --format=%B` for the message, `git branch --show-current` for the branch, and a UTC ISO 8601 timestamp from the execution environment for `git_commit_observed_at`.

## Workflow

1. Resolve the repository root and active task scope.
2. Inspect status, diffs, untracked files, branch, and recent commit style.
3. Report unrelated or suspicious changes to the caller instead of modifying them.
4. Stage only task-scoped files.
5. Reinspect the staged diff before committing.
6. Commit with a concise task-scoped message.
7. Push the commit when the remote, branch, and default-branch policy are safe to use.
8. Capture the git trace payload for the caller to persist through KOS.

## Stop Conditions

Stop and return control to the calling orchestrator when:

- suspicious files may be included in the commit
- staged changes do not match the active task scope
- unrelated user changes would be modified or reverted
- verification failed and the caller has not accepted the risk
- the branch or push destination is unclear
- the current branch is a default branch such as `main`, `master`, or `trunk` and no explicit safe policy from the work package, project configuration, or human intent permits a direct push
- the repository requires history rewriting or force-push behavior
- git authentication, hooks, or remote policy blocks commit or push
- the caller needs a human decision before continuing safely

## Verification

Verify this skill by:

- checking that its operations match loaded project knowledge and repository handoff policy
- running repository inspection commands on a dirty and clean worktree during real task handoffs
- confirming suspicious-file stop conditions prevent accidental staging
- confirming default-branch pushes stop unless explicit safe policy from the work package, project configuration, or human intent permits direct push
- confirming the trace payload fields map to the task git-trace API described by `kos-api`
