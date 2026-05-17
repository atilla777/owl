---
name: kos-document
description: Update repository documentation surfaces touched by the active KOS task and produce the documentation_update artifact.
---

# Skill: kos-document

## Purpose

`kos-document` is the workflow stage skill for updating repository documentation surfaces touched by the active task and producing a `documentation_update` artifact for durable persistence.

Use it to keep `CLAUDE.md` ancestor docs and active `LiveSkills::Skill` records in sync with the implementation diff before review begins, without touching production code.

## When To Use

Use this skill when the current task workflow status is `documenting` on a workflow that declares that stage: the `Subtask workflow` (agent_workflow_type id 3), the `Feature workflow` (id 4), or the `Bugfix workflow` (id 5). These three workflows are seeded by `Tasks::Services::EnsureSubtaskWorkflowType`, `Tasks::Services::EnsureFeatureWorkflowType`, and `Tasks::Services::EnsureBugfixWorkflowType` and all declare `documenting` between `testing` and `reviewing` with `documentation_update` as the `must_exist_before_leaving` artifact.

Do not use this skill on the legacy `Development workflow` (agent_workflow_type id 1) or on the `Container workflow` (id 2). Neither declares a `documenting` stage, so the orchestrator will never dispatch this skill against those workflows; if it is invoked anyway, stop and return a blocker.

Do not use this skill to broaden task scope, edit production code, rerun verification, perform git handoff, or transition workflow state.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- When work uncovers a repeatable project-specific pitfall, API behavior, workflow gotcha, verification issue, or other lesson that would prevent future mistakes, treat it as durable knowledge rather than private memory.
- Classify these entries with taxonomy `kind: nuance` and select existing `scope` and `topic` tags from `kos-api.list_tags`; do not invent taxonomy tags or free-form "what I learned" labels.
- Stage skills should return durable nuance candidates to the orchestrator. The orchestrator persists them through `kos-api.check_knowledge_conflicts` followed by `create_knowledge_entry` or `update_knowledge_entry` when the knowledge is not already captured.

- Treat `Tasks::Services::EnsureSubtaskWorkflowType::ARTIFACT_TEMPLATES["documentation_update"]` as the single source of truth for the `documentation_update` artifact shape. Required sections are `Updated docs`, `Skipped docs (with rationale)`, and `Verification`. Frontmatter schema requires `status` (enum `draft` or `approved`) and `summary` (string). The Feature and Bugfix workflows inherit this template via `.fetch("documentation_update")`, so a template retune is a reseed concern, not a skill edit.
- Treat the loaded task work package, the implementation diff observed through `kos-repo`, the active `LiveSkills::Skill` records returned by `kos-api`, and the required KOS knowledge context bundle for the `documenting` stage as authoritative inputs.
- Use `kos-repo` for all repository inspection. Do not run direct git commands that mutate state.
- Use `kos-api` only through the orchestrator for durable task or knowledge mutations.
- Start from the orchestrator-provided work-package and context packet; do not claim tasks, select workflow stages, or make hidden KOS mutations while documenting.
- Return the artifact body and recommended next workflow status to the orchestrator; do not secretly transition workflow state.

## Inputs

- task id, title, spec body, current workflow status, and lock version
- current `development_plan` artifact
- prior `verification_report` artifact, when present
- task implementation diff via `kos-repo` (staged and unstaged changes plus the last task-scoped commit on the active branch)
- active `LiveSkills::Skill` records via `bin/kos live_skills:retrieve PROJECT_ID --workflow-status documenting` (and any narrower `--task-type-id` or `--agent-workflow-type-id` scoping derived from the task) or, equivalently, `Kos::Client#retrieve_live_skills`
- required KOS knowledge context bundle for the `documenting` stage

## Outputs

- `documentation_update` artifact body in Markdown, with frontmatter `status` and `summary` plus required sections `Updated docs`, `Skipped docs (with rationale)`, `Verification`
- list of documentation files actually edited (paths only)
- list of `LiveSkills::Skill` records edited via `bin/kos live_skills:update`, when any
- one-line summary of documentation impact
- any blockers, scope expansions, or durable nuance knowledge candidates
- recommended next workflow status, usually `reviewing` once `documentation_update` is ready

## Doc Discovery Workflow

1. Ask `kos-repo` for the change set on the active branch (staged plus unstaged plus the last task-scoped commit) and collect the list of changed paths.
2. For each changed path, walk ancestors up to the repository root collecting any `CLAUDE.md` files. An empty ancestor set is a normal outcome today (no `CLAUDE.md` exists in the repo); record it in `Skipped docs (with rationale)` with the rationale `no CLAUDE.md ancestor found` rather than failing.
3. Call `bin/kos live_skills:retrieve PROJECT_ID --workflow-status documenting` (add `--task-type-id` and `--agent-workflow-type-id` to match the active task's scoping when known) and intersect each returned skill's `triggers` and scoping fields with the change set to surface skills whose body may need an update.
4. Union the `CLAUDE.md` set and the `LiveSkills` set into a candidate list.
5. For each candidate, decide update or skip. For each update, edit only the doc surface; for each skip, capture a one-line rationale.
6. Author the `documentation_update` body using the template shape from the Source Of Truth section.

## Scope Policy

This skill is permitted to:

- edit `.md` documentation files in the repository (including `CLAUDE.md` ancestors and skill `SKILL.md` files when they are doc surfaces, not orchestrator behavior)
- update `LiveSkills::Skill` records via `bin/kos live_skills:update`

This skill is forbidden from:

- editing Ruby, JavaScript, TypeScript, or any other production source code
- editing tests, migrations, schema files, seeds, or generated artifacts
- reorganizing or moving existing doc files; only in-place content updates are allowed
- broadening task scope, claiming tasks, or transitioning workflow status

If a documentation fix would require code changes, stop and return a blocker so the orchestrator can route back to `implementing`.

## Stop Conditions

Stop and return a clear blocker to the orchestrator when:

- the active task is not on a workflow that declares a `documenting` stage (i.e. not Subtask/Feature/Bugfix)
- the `development_plan` artifact is missing or too vague to identify the change set
- required KOS knowledge context for `documenting` is missing, blocked, failed to load, or not acceptable
- the diff cannot be obtained safely through `kos-repo`
- a needed documentation update would require editing production code or moving doc files
- existing worktree changes conflict with the doc files that must be edited
- the `bin/kos live_skills:retrieve` call (or `Kos::Client#retrieve_live_skills` fallback) fails for reasons unrelated to "no records found"
- suspicious files or generated artifacts would need to be modified without clear source-of-truth rules

An empty `CLAUDE.md` ancestor set is not a stop condition; record it as a skipped doc with rationale and continue.

## Persistence Responsibilities

This skill edits doc files and `LiveSkills::Skill` records, and returns the `documentation_update` body. The orchestrator persists the artifact through `kos-api.write_task_artifact` with public artifact key `documentation_update` and applies the workflow transition from `documenting` to `reviewing`.

## Verification

Verify this skill by checking that:

- the artifact body literally contains the required sections `Updated docs`, `Skipped docs (with rationale)`, and `Verification`
- the frontmatter contains `status` and `summary` keys matching the schema in `Tasks::Services::EnsureSubtaskWorkflowType::ARTIFACT_TEMPLATES["documentation_update"]`
- every edited file is a `.md` doc surface or a `LiveSkills::Skill` record, never production source
- every skipped candidate has a one-line rationale (including the "no CLAUDE.md ancestor found" outcome)
- the artifact key remains `documentation_update`
- the skill does not silently transition workflow status

Smoke-run procedure for this skill itself, suitable for the `testing` stage:

- Read the active branch diff through `kos-repo` and confirm the change set is non-empty.
- Walk each changed path's ancestors for `CLAUDE.md`; today the expected outcome is an empty set, which must be recorded under `Skipped docs (with rationale)` rather than treated as a failure.
- Run `bin/kos live_skills:retrieve PROJECT_ID --workflow-status documenting` and confirm the call returns a JSON envelope with a `live_skills` key. If the CLI is unavailable, fall back to `Kos::Client#retrieve_live_skills` from `lib/kos/client.rb`.
- Hand-author a sample `documentation_update` body and confirm it satisfies the template (required sections literally present, frontmatter `status` and `summary` present) by direct visual diff against `Tasks::Services::EnsureSubtaskWorkflowType::ARTIFACT_TEMPLATES["documentation_update"]`.
