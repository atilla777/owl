---
name: kos-plan
description: Turn a loaded KOS task work package into a concrete development plan artifact.
---

# Skill: kos-plan

## Purpose

`kos-plan` is the workflow stage skill for turning a loaded KOS task work package into a concrete development plan artifact.

Use it to make implementation scope explicit before code changes begin while keeping KOS task state and artifact storage authoritative.

## When To Use

Use this skill when the current task workflow status is `planning` on any of the three workflow types that declare a planning stage: `Subtask workflow`, `Feature workflow`, or `Bugfix workflow`. Container workflow does not declare a `planning` stage and never dispatches here.

Do not use this skill to implement code, run verification, perform review, commit changes, or choose the next task.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- When work uncovers a repeatable project-specific pitfall, API behavior, workflow gotcha, verification issue, or other lesson that would prevent future mistakes, treat it as durable knowledge rather than private memory.
- Classify these entries with taxonomy `kind: nuance` and select existing `scope` and `topic` tags from `kos-api.list_tags`; do not invent taxonomy tags or free-form "what I learned" labels.
- Stage skills should return durable nuance candidates to the orchestrator. The orchestrator persists them through `kos-api.check_knowledge_conflicts` followed by `create_knowledge_entry` or `update_knowledge_entry` when the knowledge is not already captured.

- Treat the task work package loaded through `kos-api` as authoritative.
- Read task requirements from `spec.body` or the task spec body included in the work package.
- Read existing `development_plan` artifacts before replacing or refining them.
- Use the KOS knowledge context bundle as the primary project-context source.
- Inspect repository source files when code context is needed, but do not use local roadmap/spec/rule Markdown files as active workflow state after migration.
- Treat repository Markdown files as historical or fallback context only when KOS retrieval is unavailable and the human explicitly approves fallback.
- Start from the orchestrator-provided work-package and context packet; do not claim tasks, select workflow stages, or make hidden KOS mutations while planning.
- Return plan output to the orchestrator; do not secretly transition workflow state.

## Inputs

- task id, title, current workflow status, and lock version
- task spec body and relevant history from the work package
- current artifacts, especially `development_plan` when it exists
- workflow definition, allowed transitions, transition blockers, and artifact requirements
- repository root path when code context is needed to make the plan concrete
- required KOS knowledge context bundle for the planning stage

## Outputs

- `development_plan` artifact body in Markdown
- concise implementation scope summary
- expected files or areas to inspect or change
- verification plan with the smallest relevant checks first
- risks, blockers, open questions, or scope decisions that require human input
- recommended next workflow status, usually `implementing` when no blocker remains

## Development Plan Shape

Use this structure unless the active workflow type's `development_plan` template requires a different one:

```markdown
# Development Plan

## Goal

<Concrete outcome this task will deliver.>

## Scope

- <Included work>

## Non-Goals

- <Deferred work>

## Implementation Steps

1. <Smallest ordered step>

## Verification

- <Relevant check>

## Risks And Stop Conditions

- <Concrete risk or blocker, if any>
```

### Bugfix mode (`Bugfix workflow`) — Regression Test section is required

When the active task's `agent_workflow_type.name` is `Bugfix workflow`, the `development_plan` template (`EnsureBugfixWorkflowType::BUGFIX_DEVELOPMENT_PLAN_TEMPLATE`) extends the default `required_sections` with an explicit `Regression Test` section placed immediately after the `Test plan` section. The plan body MUST include both `## Test plan` and `## Regression Test` as literal headings — `Tasks::AgentArtifacts::TemplateValidator` does byte-for-byte matching against rendered `##` headings and will reject the artifact otherwise.

`Regression Test` content must name the concrete failing test (file, describe/context, and example name) that reproduces the bug before the fix lands and turns green after the fix. Generic statements such as "add coverage" are not sufficient. If no failing-test reproduction is possible, stop and return a blocker rather than fabricating a section.

For all other workflow types (`Subtask workflow`, `Feature workflow`) the default `development_plan` template applies and `Regression Test` is not required.

## Workflow

1. Receive the current task work package from the orchestrator; any delegated mechanical API read must be performed by the orchestrator or API helper, not by this planning stage skill.
2. Confirm the required KOS knowledge context bundle is present and has an acceptable status.
3. Confirm the spec is clear enough to plan.
4. Inspect only the repository files needed to understand the smallest correct implementation.
5. Draft or update the `development_plan` artifact body.
6. Identify any unresolved decisions, prerequisites, or scope expansions.
7. Return structured output to the orchestrator for `write_task_artifact` with artifact key `development_plan`.
8. Recommend transition to `implementing` only when there are no blockers or human decisions.

## Stop Conditions

Stop and return a clear blocker to the orchestrator when:

- task requirements are too vague to choose a safe implementation path
- required KOS knowledge context is missing, blocked, failed to load, or not acceptable for planning
- the plan requires a product, architecture, data migration, or scope decision the human must make
- the task depends on a prerequisite that is not part of the current task
- the work package is missing spec, artifact, workflow, or lock data needed for safe persistence
- repository context conflicts with the task spec in a way that changes scope

## Persistence Responsibilities

This skill produces the `development_plan` body and a recommended workflow transition. The orchestrator persists the artifact through `kos-api` and applies any workflow transition with the latest lock version.

## Verification

Verify this skill by checking that:

- the plan directly traces to the task spec
- implementation steps are small, ordered, and scoped
- verification commands or checks are named explicitly
- unresolved questions are returned as blockers instead of being hidden inside the plan
- the artifact key remains `development_plan`
- for `Bugfix workflow` tasks, the plan body contains both `## Test plan` and `## Regression Test` literal headings and the `Regression Test` section names a concrete failing test
