---
name: kos-orchestrator
description: Continue or claim KOS tasks through the canonical orchestration workflow.
---

# Skill: kos-orchestrator

## Purpose

`kos-orchestrator` is the top-level KOS-owned skill for executing a task workflow from persisted KOS application state.

Use it to claim or load actionable task work, inspect the current work package, dispatch the appropriate stage skill, persist stage outputs through KOS API operations, and continue until the task is complete or a real blocker requires human input.

## When To Use

Use this skill when the human or an agent wants to:

- continue the next actionable KOS task without manually choosing workflow stages
- resume an interrupted task flow from KOS state
- run a development task through planning, implementation, verification, documenting, review, autonomous delivery, and completion reporting
- coordinate stage skills while keeping KOS API state authoritative

Do not use this skill to brainstorm new tasks from vague ideas. Use `kos-brainstorm` first when the task does not already exist or the desired outcome is not clear enough to plan.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- When work uncovers a repeatable project-specific pitfall, API behavior, workflow gotcha, verification issue, or other lesson that would prevent future mistakes, treat it as durable knowledge rather than private memory.
- Classify these entries with taxonomy `kind: nuance` and select existing `scope` and `topic` tags from `kos-api.list_tags`; do not invent closed-vocabulary tags (`kind`, `scope`, `topic`) or free-form "what I learned" labels. The `subtopic` group is the only open-vocabulary dimension — pass `subtopic:` to `create_knowledge_entry` / `update_knowledge_entry` to mint a free-form subtopic value at write time when an existing triple is too coarse.
- Stage skills should return durable nuance candidates to the orchestrator. The orchestrator persists them through `kos-api.check_knowledge_conflicts` followed by `create_knowledge_entry` or `update_knowledge_entry` when the knowledge is not already captured.

- Treat KOS API task state, workflow definitions, task specs, and task agent artifacts as authoritative.
- Use `kos-api` for all project, task, artifact, workflow transition, knowledge, and git-trace operations. Routine API reads and simple writes may be delegated to the configured KOS API subagent as mechanics, but the orchestrator owns the workflow decision, selected operation, lock-version source, and whether the result should be persisted.
- Accumulate a compact orchestration run trace for meaningful workflow runs and persist it through `record_task_orchestration_run` before stopping, blocking, or completing.
- Use `kos-repo` for repository inspection, verification commands, scoped staging, commit, push, and git trace capture.
- Reload the task work package before each stage decision that depends on current workflow status, lock versions, transition blockers, artifact requirements, or recent history.
- Load the tag dictionary through `kos-api.list_tags` before context retrieval. Treat tag group and tag descriptions as the guide for selecting retrieval tags and interpreting returned knowledge.
- Load the required knowledge context bundle through `kos-api.get_knowledge_context` before dispatching a stage skill.
- Do not depend on hidden local files, private notes, or prior in-memory context to resume a task after interruption.
- Keep this skill in `skills/kos-orchestrator/` while it is experimental. Do not move it into `.opencode/skills` until the application skill workflow has been proven end to end.

## Inputs

- optional project id or project slug; default to the current repository project through `kos-api.resolve_or_create_current_project` when the caller provides no project
- optional task id; when omitted, claim the next task through KOS API deterministic selection logic
- optional task selection mode: `any` (default), `execution`, or `specification`; use explicit modes when the human asks to limit the kind of work instead of relying on free-form intent text
- optional actor user id for mutating KOS API calls
- optional human intent text, such as continue, resume, or finish current work
- repository root path for implementation, verification, review, and delivery stages

## Outputs

- selected or claimed task work package
- stage result persisted through the appropriate KOS artifact or task operation
- workflow transitions applied through KOS API with current lock versions
- git trace persisted after successful commit and push when the task reaches the `delivering` stage
- concise Russian human-readable report when the task completes or stops for a blocker
- explicit stop reason and required human decision when the workflow cannot continue safely

## Dispatch Model

The orchestrator chooses the next stage from the loaded work package rather than from local roadmap files.

## Subagent Policy

Constants define the routing. Use this table:

| Work type | Agent type | Skill |
|----------|-----------|-------|
| KOS API reads and simple writes | `kos-standard-agent` | `kos-api` |
| Repository inspection and scoped git operations | `kos-standard-agent` | `kos-repo` |
| Verification | `kos-standard-agent` | `kos-verify` |
| Repository delivery (autonomous commit + push) | `kos-standard-agent` | `kos-deliver` |
| Completion report | `kos-standard-agent` | `kos-completion-report` |
| New task brainstorming | `kos-advanced-agent` | `kos-brainstorm` |
| Intake / specification (intent_brief or specification) | `kos-advanced-agent` | `kos-specify` |
| Clarification | `kos-advanced-agent` | `kos-clarify` |
| Analysis (acceptance_criteria + analysis_report, plus outgoing_tasks for Container) | `kos-advanced-agent` | `kos-analyze` |
| Planning | `kos-advanced-agent` | `kos-plan` |
| Implementation | `kos-advanced-agent` | `kos-implement` |
| Documentation update | `kos-advanced-agent` | `kos-document` |
| Review | `kos-advanced-agent` | `kos-review` |
| Project memory import | `kos-advanced-agent` | `kos-project-memory-import` |

When in doubt, prefer `kos-advanced-agent`.

Before launching any specialist subagent, include the current work package essentials, current workflow status, lock versions, required artifact keys, and knowledge context status in the delegated prompt. The subagent should start from this packet instead of rediscovering KOS state from scratch, claiming tasks, or making hidden workflow-state changes.

Primary inputs from the work package:

- `task.workflow_status`
- `workflow.current_status`
- `workflow.allowed_transitions`
- `workflow.transition_blockers`
- `workflow.definition`
- `workflow.artifact_requirements`
- `spec.body`
- current `artifacts`
- `history`
- `retrieval_hints.required_knowledge_context`
- `locks.task.lock_version`

Default stage mapping:

The mapping is keyed on `workflow.current_status` and is scoped by `agent_workflow_type.name`. The four canonical AgentWorkflowTypes are seeded by `Tasks::Services::EnsureContainerWorkflowType`, `EnsureSubtaskWorkflowType`, `EnsureFeatureWorkflowType`, and `EnsureBugfixWorkflowType`. Every status below is a real `workflow_status` declared by one of those services; no `awaiting_*` alias is dispatched.

Container workflow (`Container workflow`) — statuses `idea → exploring → clarifying → analyzing → ready_to_plan → done` (+ `blocked`):

- `idea`: stop and report. Container tasks in `idea` are roadmap grouping records waiting for human direction; the orchestrator does not auto-advance them. Dispatch to `kos-brainstorm` only when the human explicitly asks to mature the idea into a brief.
- `exploring`: dispatch `kos-specify` and persist an `intent_brief` artifact.
- `clarifying`: dispatch `kos-clarify` and persist a `clarification_log` artifact.
- `analyzing`: dispatch `kos-analyze` and persist `acceptance_criteria`, `analysis_report`, and `outgoing_tasks` artifacts.
- `ready_to_plan`: confirm the `outgoing_tasks` artifact is present and transition to `done`; the `Tasks::Services::UpdateWorkflowStatus` service runs `SpawnOutgoingTasks` inside the transition transaction to create child Subtask tasks.

Subtask workflow (`Subtask workflow`) — statuses `specifying → planning → implementing → testing → documenting → reviewing → delivering → done` (+ `blocked`):

- `specifying`: dispatch `kos-specify` in Subtask mode (the body is pre-seeded by `SpawnOutgoingTasks`; this stage only fills missing required sections) and persist the `specification` artifact.
- `planning`: dispatch `kos-plan` and persist a `development_plan` artifact.
- `implementing`: dispatch `kos-implement` against the current development plan.
- `testing`: dispatch `kos-verify` and persist a `verification_report` artifact before documenting, review, or follow-up implementation.
- `documenting`: dispatch `kos-document` and persist a `documentation_update` artifact.
- `reviewing`: dispatch `kos-review` and persist a `review_report` artifact, including the Documentation Rationale Check on `documentation_update`.
- `delivering`: dispatch `kos-deliver` through `kos-repo` for autonomous commit + push + git trace capture. After a successful trace, write the `completion_report` and transition to `done` without a human approval gate.

Feature workflow (`Feature workflow`) — statuses `specifying → clarifying → analyzing → planning → implementing → testing → documenting → reviewing → delivering → done` (+ `blocked`):

- `specifying`: dispatch `kos-specify` in Feature mode and persist the `specification` artifact.
- `clarifying`: dispatch `kos-clarify` and persist a `clarification_log` artifact.
- `analyzing`: dispatch `kos-analyze` in Feature mode and persist `acceptance_criteria` and `analysis_report` artifacts (no `outgoing_tasks` — Feature tasks do not spawn children).
- `planning`, `implementing`, `testing`, `documenting`, `reviewing`, `delivering`: same as the Subtask mapping above (Feature workflow shares the execution stages with Subtask workflow).

Bugfix workflow (`Bugfix workflow`) — statuses `specifying → analyzing → planning → implementing → testing → documenting → reviewing → delivering → done` (+ `blocked`):

- `specifying`: dispatch `kos-specify` in Bugfix mode and persist the `specification` artifact (Bugfix-shaped sections: `Current Behavior`, `Expected Behavior`, `Unchanged Behavior`, `Affected Versions`, `Reproduce Steps`).
- `analyzing`: dispatch `kos-analyze` in Bugfix mode and persist `acceptance_criteria` and the root-cause `analysis_report` (sections: `Root Cause`, `Fix Scope`, `Regression Risk`, `Mitigations`). No `outgoing_tasks` and no `clarification_log` (Bugfix has no clarifying stage).
- `planning`: dispatch `kos-plan` in Bugfix mode and persist a `development_plan` artifact that includes the required `## Test plan` and `## Regression Test` literal sections.
- `implementing`, `testing`, `documenting`, `reviewing`, `delivering`: same as the Subtask mapping above.

Statuses shared by every workflow type:

- `blocked`: stop and report the blocker unless the loaded state contains a concrete unblock action that does not require human judgment.
- `done`: stop with a short Russian completion report; do not mutate the task further.

After successful delivery (the `delivering → done` step), the orchestrator writes the `completion_report` artifact through `kos-completion-report`, then applies the transition to `done`. No human approval gate exists between `reviewing` and `done` when verification and review both pass — the `delivering` stage is autonomous.

Legacy note: the historical `Development workflow` (agent_workflow_type id 1) used `awaiting_plan_approval`, `awaiting_git_approval`, and other `awaiting_*` aliases. None of the four canonical workflow types declares those statuses; the orchestrator no longer dispatches them.

Stage skills may use other names as the skill set evolves, but the orchestrator must keep the boundary clear: stage skills perform focused work from the supplied packet and return structured results; the orchestrator decides what to persist, what transition to apply, and whether to continue.

## Workflow

1. Resolve actor identity and project context through `kos-api`; when no project is provided, resolve or create the current repository project before claiming work.
2. If a task id is provided, load that task work package; otherwise call `claim_next_actionable_task` for the project with the selected mode, which may resume this agent's existing claimed unfinished work before claiming new work.
3. Stop with a no-work report when the API returns no resumable or selectable task. Do not report "no tasks" merely because execution work is empty when specification/idea work exists; default `any` selection should claim specification work after execution work. Container tasks are roadmap grouping records and are not auto-claimed.
4. Read the task spec, workflow definition, transition blockers, artifact requirements, current artifacts, history, retrieval hints, and lock versions from the work package.
5. Load the tag dictionary and verify that `kind`, `scope`, and `topic` groups and their descriptions are present. Use those descriptions to understand which tags the context retrieval endpoint or any targeted `search` call should use.
6. Load the required knowledge context bundle for the current task and stage using the endpoint and stage in `retrieval_hints.required_knowledge_context`.
7. Compare the bundle status to `retrieval_hints.required_knowledge_context.acceptable_statuses`; `empty_acceptable` is valid only when the work package explicitly allows it for the current stage.
8. If transition blockers, missing required inputs, missing taxonomy descriptions, or an invalid knowledge context status prevent safe progress, stop with a plain-language explanation and numbered human options.
9. Dispatch the current workflow status to the matching stage behavior and pass the knowledge context bundle as an input.
10. Persist stage output through `kos-api`, such as `write_task_artifact` (including the `specification` artifact for the specifying stage), `transition_task_workflow`, or knowledge operations.
11. When a stage returns durable nuance candidates, load `list_tags`, require an existing `kind: nuance` tag plus suitable existing `scope` and `topic` tags, run `check_knowledge_conflicts`, then create or update the matching knowledge article through `create_knowledge_entry` or `update_knowledge_entry`.
12. Reload the work package after each persisted change that can affect status, blockers, artifact requirements, or locks.
13. Continue to the next obvious stage automatically when there is no unresolved question, failed-check decision, suspicious file, scope expansion, stale lock conflict, or push concern.
14. When `kos-deliver` succeeds in the `delivering` stage, persist final git trace through `finalize_task_git_trace`. Treat both `new_commit` and `existing_head_no_changes` as successful delivery results when the delivery report includes a complete trace payload.
15. Persist the compact orchestration run trace with skills invoked, subagents used, KOS API operations, direct-client fallback usage, verification commands, and handoff result when this run performed meaningful work.
16. Write or update a `completion_report` artifact when the workflow supports it, then move the task to the configured completed status when the workflow allows it.
17. Return a concise Russian report describing what changed for the end user, what changed operationally for the human/operator, what was verified, and the git trace when available.

## Stage Persistence Responsibilities

The orchestrator is responsible for persisting stage outputs. Stage skills should return structured results and should not secretly advance task state.

Expected persistence by stage:

- exploring (Container): `write_task_artifact` with public artifact key `intent_brief`
- specifying (Subtask / Feature / Bugfix): `write_task_artifact` with public artifact key `specification`; the same call may set the agent-authored `tasks.summary` (via `update_task`) when summary changes
- clarifying (Container / Feature): `write_task_artifact` with public artifact key `clarification_log`
- analyzing (Container / Feature / Bugfix): `write_task_artifact` with public artifact keys `acceptance_criteria` and `analysis_report`; for Container also `outgoing_tasks`
- ready_to_plan (Container): no new artifact; transition to `done` so `Tasks::Services::UpdateWorkflowStatus` runs `SpawnOutgoingTasks` inside the transaction
- planning (Subtask / Feature / Bugfix): `write_task_artifact` with public artifact key `development_plan`
- implementing: no direct KOS mutation unless implementation discovers a blocker, scope expansion, or durable nuance knowledge to capture
- testing: `write_task_artifact` with public artifact key `verification_report` before transitioning to documenting (or back to implementing on failure)
- documenting (Subtask / Feature / Bugfix): `write_task_artifact` with public artifact key `documentation_update` before transitioning to reviewing
- reviewing: `write_task_artifact` with public artifact key `review_report`
- delivering: `finalize_task_git_trace` after `kos-repo` commits and pushes successfully, or after `kos-deliver` returns `existing_head_no_changes` for a no-diff verification/review/documentation task with a complete current `HEAD` trace. The Rails service method `finalize_task_no_op_git_handoff` and the CLI command `bin/kos task:git-handoff:no-op` keep their historical names; only the skill is renamed to `kos-deliver`.
- completion: `write_task_artifact` with public artifact key `completion_report`, then transition to the configured `done` state

## Transition Rules

- Use `transition_task_workflow` for workflow-state changes.
- Include the latest task lock version from the work package or task response when available.
- Never force a transition that is blocked by artifact requirements, workflow definition rules, stale lock errors, failed checks requiring judgment, or unclear human requirements.
- If the API reports a stale lock, reload the work package once and retry only when the desired change is still valid. Ask the human or stop with a conflict report when the reload changes the decision.
- Do not treat planning entry, implementation start, the `reviewing → delivering` transition, commit, or push as automatic stopping points. The four canonical workflow types declare no `awaiting_*` approval gate; stop only when there is a real decision or safety concern.

## Live Skills From Stage Trace

Stage skills may return a `proposed_live_skill` field in their orchestration trace when they discover reusable guidance that should become a `LiveSkills::Skill` rather than a one-shot note. The orchestrator owns persistence of these candidates; stage skills must not write the `LiveSkills::Skill` record directly.

When a stage trace includes `proposed_live_skill`, the orchestrator must:

- call `LiveSkills::Services::ProposeSkillFromTrace` (in-process) or, when running against a remote KOS, mirror the call through `bin/kos live_skills:create` followed by `bin/kos live_skills:propose` so the resulting record ends up in `status: "proposed"` with the current task id and the current actor user id attributed
- never write `LiveSkills::Skill` rows by direct ActiveRecord or by `Kos::Client#create_live_skill` outside of `ProposeSkillFromTrace`'s flow — the lifecycle column is the only mechanism that gates new skills behind human approval and bypassing it leaks unreviewed guidance into other agents' retrieval

Expected `proposed_live_skill` field shape (all fields optional except `title` and `body`):

```json
{
  "title": "Short title",
  "body": "Skill body in Markdown",
  "summary": "One-line summary",
  "triggers": ["keyword", "phrase"],
  "auto_inject": false,
  "workflow_status": "planning",
  "task_type_id": null,
  "agent_workflow_type_id": null,
  "project_id": null
}
```

A `proposed` skill is invisible to retrieval. A human reviewer must call `bin/kos live_skills:approve PROJECT_ID SKILL_ID LOCK_VERSION --actor-type human` (or the equivalent HTTP endpoint) before the skill becomes visible to other agents.

If the human has not approved the skill by the time the task reaches completion, that is not a blocker — proposed skills are intentionally durable and survive task close.

## Repository Delivery

Use `kos-repo` and `kos-deliver` when a task reaches the `delivering` stage.

Repository delivery must:

- be gated on a passing `verification_report` and `review_report` (and an approved `documentation_update` when the workflow declares a `documenting` stage); `kos-deliver` performs this pre-flight check before doing anything else
- inspect status, staged diff, unstaged diff, current branch, and recent commit style
- screen for suspicious files before staging
- stage only files scoped to the active task
- commit with a concise task-scoped message when scoped changes exist
- push the current branch when a new commit was created and the destination is clear and safe
- for verification-only, review-only, documentation-only, or otherwise intentional no-change tasks, accept `existing_head_no_changes` from `kos-deliver`, persist the current `HEAD` trace, and continue toward `done` without asking the human for approval
- return branch, commit SHA, commit message, observed timestamp, and delivery mode for KOS git trace persistence

Stop before commit or push when the repository state includes suspicious files, unrelated staged changes, failed checks needing judgment, unclear branch/remote destination, or any required history rewrite.

Note on legacy names preserved: the Rails service method `Tasks::Services::FinalizeTaskWorkflow#finalize_task_no_op_git_handoff` and the CLI command `bin/kos task:git-handoff:no-op` are intentionally NOT renamed. Only the skill is renamed from `kos-git-handoff` to `kos-deliver`.

## Stop Conditions

Stop and return control to the human when:

- no project can be resolved safely
- no actor identity is available for a required mutating operation
- no actionable task exists
- task requirements are too unclear to plan
- the work package is missing workflow data required for safe dispatch
- required knowledge context is missing, blocked, failed to load, or has a status outside the work package's acceptable statuses
- workflow transition blockers require human input
- implementation discovers a prerequisite or scope expansion outside the current task
- verification fails and the next action requires judgment rather than an obvious fix
- review finds a required fix that cannot be made within the approved scope
- suspicious or unrelated repository changes make commit scope ambiguous
- no scoped repository changes exist and the task artifacts do not clearly support an intentional no-change delivery
- push destination, authentication, or repository policy is unclear
- KOS API is unavailable or rejects a required operation in a way that cannot be resolved by one reload

When stopping for a human decision, report:

- current task id and title
- current workflow status
- what was done in this run
- what blocks the next step
- one explicit `Что мне нужно от тебя сейчас` sentence
- numbered options that the human can answer with directly
- use Russian for the entire stop report, including headings and options

## Verification

Verify this skill by:

- checking that every documented API operation is listed in `skills/kos-api/SKILL.md`
- checking that repository delivery behavior matches `skills/kos-repo/SKILL.md` and `skills/kos-deliver/SKILL.md`
- running one dry workflow walkthrough for an actionable task through claim, work-package load, planning artifact write, workflow transition, autonomous delivery, git trace persistence, and completion report
- confirming interrupted-flow recovery starts by reloading the work package instead of relying on prior local context
- confirming stop conditions produce a clear human decision request rather than silently changing scope
