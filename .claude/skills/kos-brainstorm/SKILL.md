---
name: kos-brainstorm
description: Turn a rough human idea into trackable KOS tasks with enough specification detail for planning.
---

# Skill: kos-brainstorm

## Purpose

`kos-brainstorm` is the KOS-owned skill for turning a rough human idea into one or more trackable KOS tasks with enough specification detail for later planning.

Use it to guide the discussion before implementation work starts, preserve the reasoning behind task boundaries, and create tasks through the KOS API instead of editing database records or repository files directly.

## When To Use

Use this skill when the human wants to:

- discuss a new product, architecture, workflow, or maintenance idea
- create a new task from a rough request
- split a broad idea into a parent task and concrete child tasks
- refine a task specification before planning or implementation
- decide whether an idea is ready to enter the roadmap

Do not use this skill to implement the task, run repository edits, perform git handoff, or silently make the new task current. Those actions belong to orchestrator, stage, and repository skills.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- When work uncovers a repeatable project-specific pitfall, API behavior, workflow gotcha, verification issue, or other lesson that would prevent future mistakes, treat it as durable knowledge rather than private memory.
- Classify these entries with taxonomy `kind: nuance` and select existing `scope` and `topic` tags from `kos-api.list_tags`; do not invent closed-vocabulary tags (`kind`, `scope`, `topic`) or free-form "what I learned" labels. The `subtopic` group is the only open-vocabulary dimension — pass `subtopic:` to mint a free-form value at write time when an existing `{kind,scope,topic}` triple is too coarse.
- Stage skills should return durable nuance candidates to the orchestrator. The orchestrator persists them through `kos-api.check_knowledge_conflicts` followed by `create_knowledge_entry` or `update_knowledge_entry` when the knowledge is not already captured.

- Use `kos-api` for task creation, spec writes, and work-package reads.
- Treat task `spec_body` in KOS as the primary task-level specification once the task exists.
- Treat KOS project/task state as authoritative for workflow status, task selection, and task specs.
- Use imported KOS knowledge context for project rules, communication policy, and durable conventions.
- Repository Markdown files such as legacy specs or legacy rules are historical/fallback context after migration; do not update them as active workflow state unless the human explicitly asks for a legacy repository artifact.
- The KOS repository `skills/kos-*` directories are the install source for runtime KOS skills copied into target projects.

## Inputs

- human idea or problem statement
- optional project id or project slug; default to the current repository project when the caller is operating from a repository checkout
- optional actor user id for API attribution
- optional parent task id when the idea belongs under existing work
- optional task type, agent workflow type, and priority preferences (see Workflow Type Selection below)
- existing KOS roadmap, task, or work-package context, when relevant
- required knowledge context bundle from KOS when the brainstorm belongs to an existing project or task area

## Workflow Type Selection

Every persisted task must be created under one of the four KOS AgentWorkflowTypes. The choice locks in the stage sequence the orchestrator will later dispatch, so make it explicit during brainstorming rather than letting the API fall back to a default. The four canonical workflow types and their `name` strings, as seeded by `Tasks::Services::Ensure*WorkflowType`, are:

- `Container workflow` — brainstorm/specification container. Stages: `idea → exploring → clarifying → analyzing → ready_to_plan → done`. Use this when the idea is a roadmap-level grouping that will spawn child tasks via `outgoing_tasks` rather than be implemented directly. Container tasks are never auto-claimed by the orchestrator; they are gathering records that produce children.
- `Subtask workflow` — child task spawned by a Container's `outgoing_tasks`. Stages: `specifying → planning → implementing → testing → documenting → reviewing → delivering → done`. Use this only when the parent is a Container task that has reached `ready_to_plan` and is about to spawn. Brainstorm does not normally create Subtask tasks directly; `SpawnOutgoingTasks` creates them.
- `Feature workflow` — standalone Development feature (no parent Container). Stages: `specifying → clarifying → analyzing → planning → implementing → testing → documenting → reviewing → delivering → done`. Use this when the idea is a single coherent feature that does not need a Container grouping but still needs its own clarification and analysis pass.
- `Bugfix workflow` — standalone Development bug fix. Stages: `specifying → analyzing → planning → implementing → testing → documenting → reviewing → delivering → done`. Use this when the idea is reproducing and fixing a defect. The `analyzing` artifact is a root-cause `analysis_report` (Root Cause / Fix Scope / Regression Risk / Mitigations); the `development_plan` carries an explicit `Regression Test` section.

Choosing logic to apply during the brainstorm:

1. If the idea is a roadmap grouping that will produce multiple independently-deliverable children, propose a `Container workflow` parent. Do not also create the children in this brainstorm; the container's `analyzing` stage produces the `outgoing_tasks` artifact that spawns them.
2. If the idea is a single deliverable feature, propose a `Feature workflow` task.
3. If the idea is a defect to reproduce and fix, propose a `Bugfix workflow` task.
4. Do not propose a `Subtask workflow` task directly. Subtask records are created by `SpawnOutgoingTasks` from a Container's `outgoing_tasks` artifact, not by `create_task` calls from this skill.

Confirm the selected workflow type with the human before persistence whenever the choice is ambiguous (for example, when an idea could plausibly be either a Feature or a Container with one child).

## Outputs

- clarified problem statement
- desired outcome and success criteria
- explicit in-scope and out-of-scope notes
- recommended task shape: single task, parent task with children, or no task yet
- task title, body, and spec body draft
- optional child task drafts with parent-child relationship
- API creation payloads and created task ids when persistence succeeds
- stop reason and unresolved questions when the idea is not ready to persist

## Discussion Workflow

1. Restate the idea in plain language.
2. Resolve project context, using the current repository project when the caller omits project input.
3. Load or receive the relevant KOS knowledge context bundle for the project/task area before shaping the task.
4. Identify the user-visible or operator-visible outcome.
5. Ask only for missing information that blocks a useful task spec.
6. Separate requirements from implementation guesses.
7. Define the smallest task that can deliver useful progress.
8. Decide whether decomposition is needed.
9. Draft the task title, body, spec body, priority, task type, and workflow type.
10. Persist the task or task tree through `kos-api` when the idea is clear enough.
11. Report created task ids and whether the task was left non-current or selected for immediate execution.

## Clarification Rules

Ask a short numbered question when the next step depends on a concrete choice, such as:

- whether the idea should be tracked now or kept as discussion
- whether to create one implementation task or a parent task with subtasks
- whether the new task should be started immediately or left in the backlog
- which project should own the task when project context is ambiguous
- which outcome is more important when scope tradeoffs conflict

Before numbered options, explain in one to three sentences what decision is needed and what changes based on the answer.

## Task Shaping Rules

Prefer one task when:

- the idea has one clear deliverable
- the implementation can be planned as a single coherent change
- splitting would create speculative coordination overhead
- child tasks would not be independently useful or reviewable

Use a parent task with child tasks when:

- the idea contains multiple independently deliverable outcomes
- parts can be planned, implemented, or reviewed separately
- sequencing matters and should remain explicit
- the parent represents a larger initiative that should preserve traceability

Do not create many speculative subtasks. If decomposition is uncertain, create the smallest useful parent task and record likely follow-ups in the spec instead.

## Spec Body Template

Use this shape for new task specs unless the caller provides a stronger format:

```markdown
# <Task title>

## Problem

<What problem or opportunity this task addresses.>

## Goal

<The concrete outcome this task should deliver.>

## Scope

- <Included requirement>

## Non-Goals

- <Deferred or explicitly excluded work>

## Acceptance Criteria

- <Observable condition that means the task is done>

## Notes

- <Relevant decisions, constraints, or open questions>
```

Keep the spec detailed enough for a later planning skill to proceed without reopening the full brainstorm, but avoid locking in implementation details before code context is loaded.

## API Persistence

Use `kos-api` operations instead of direct database writes:

- `create_task(project_id, title:, body:, status:, parent_id:, agent_workflow_type_id:)` — always pass the explicit `agent_workflow_type_id` chosen under Workflow Type Selection; do not let the API fall back to a default workflow type
- `write_task_spec(project_id, task_id, body:, lock_version:)`
- task update operations for priority and workflow status when supported by the current API

New tasks start in the initial workflow state of their AgentWorkflowType: `idea` for `Container workflow`, `specifying` for `Feature workflow` and `Bugfix workflow`. Do not mark a new task current unless the human explicitly asks to start it now.

Do not create `Subtask workflow` tasks from this skill. Subtasks are spawned by `Tasks::Services::SpawnOutgoingTasks` when a Container task transitions from `ready_to_plan` to `done`. If the brainstorm produces what feels like a subtask but no parent Container exists, propose a `Feature workflow` task instead and discuss whether a Container is warranted.

For Container brainstorms that should preserve traceability to follow-up work, capture likely children in the Container task's `spec_body` Notes section. The actual decomposition lives in the `outgoing_tasks` artifact produced later during the Container's `analyzing` stage.

## Repository Spec Transition

KOS task `spec_body` is the durable task-local requirement source. Repository-readable specs remain a transition artifact only for workflows that explicitly still require them.

When repository specs are required:

- use the `KOS-001-short-kebab-case-title.md` naming pattern when a repository task id exists
- keep repository spec content aligned with task `spec_body`
- avoid creating repository specs for speculative ideas that have not become tasks

When repository specs are not required, persist the brainstorm result through KOS only.

## Stop Conditions

Stop and return control to the human or orchestrator when:

- the problem or desired outcome is still unclear
- project ownership is ambiguous
- required KOS knowledge context is missing, blocked, or failed to load for a project-owned task idea
- the idea depends on a product or architecture decision the human must make
- decomposition would create speculative subtasks without clear deliverables
- the API cannot create or update the needed task records
- actor identity is missing for mutating API operations that require attribution
- the human asks to brainstorm without creating a task yet

## Verification

Verify this skill by:

- checking that its API operations match `skills/kos-api/SKILL.md`
- walking through one single-task brainstorm and one parent-child decomposition scenario
- confirming new tasks are not made current unless explicitly requested
- confirming the resulting `spec_body` is sufficient for a planning skill to continue
