---
name: owl-step-run
description: Execute any Owl workflow step generically by reading its per-step context bundle through `owl step show` and producing the declared artifact — no hardcoded step type knowledge.
triggers: ["owl step run", "run owl step", "execute owl step", "owl step generic"]
---

> Follows [Owl skill conventions](../_owl_conventions.md) — numbered
> prompts, autonomous-by-default execution, overlay composition.

## Purpose

`owl-step-run` is the universal step execution skill. One skill executes any step on any seeded or custom workflow because the step-specific behaviour lives in the workflow's per-step `context` (inline `step.context` string or referenced `step.context_file`), not in the skill body.

The skill reads the merged bundle from `owl step show`, interprets the step's purpose and acceptance criteria from the supplied `context` (composed with project overlays and the task's prior artifacts), generates the artifact body declared by `artifact_template`, writes it at the path returned by `owl artifact resolve`, validates it through `owl artifact validate`, and completes the step via `owl step complete`.

## When To Use

- The orchestrator (or a human) names a ready step on an Owl task and asks you to execute it.
- The step in the workflow YAML declares either an inline `context` block or a `context_file` reference — those carry the actual instructions for this particular step.
- You are working through a seeded or custom workflow and prefer one universal executor over per-step specialised skills.

Do not use this skill to plan task scope, decide step ordering, or interpret workflow definitions outside the supplied bundle. Workflow choice and step ordering belong to the Owl CLI graph (`owl task ready-steps`); product or scope decisions belong to the human.

## Inputs

- `TASK-ID` (from `owl task current --json` or an explicit argument).
- `STEP-ID` chosen from `owl task ready-steps TASK-ID --json` (or the value `owl-orchestrator` handed you).
- The bundle returned by `owl step show TASK-ID STEP-ID --json`:
  - `step` — the step payload (id, status, declared inputs, declared `creates` artifact key, optional `interactive: true`) without the `context` field.
  - `context` — the per-step instruction text (string or null when the step has no per-step context).
  - `overlays` — array of `{ source, body, warning }` project overlays (`.owl/overlays/<step>.md`, `docs/ai/<step>.md`, or explicit paths from `.owl/config.yaml: context_overlays.<step>`).
  - `artifact_template` — `{required_sections, frontmatter_schema}` for the step's declared artifact (null when the step produces no artifact).
  - `execution_mode` — workflow-level mode (`autonomous_after_brief`, `autonomous`, `interactive`, or null).
  - `task` — `{id, title, artifacts}` where `artifacts` is a hash `{ artifact_key => body }` of every artifact already written for this task.

## Outputs

- When the step declares an artifact: a file written at the path returned by `owl artifact resolve`, containing the required sections and frontmatter from `artifact_template`, validated `ok: true` by `owl artifact validate`.
- When the step has no artifact (for example, a pure code-change or CLI step): the side effect described in `context` (repository changes, an `owl publish` invocation, etc.). No artifact is required.
- Step status advanced through `owl step complete TASK-ID STEP-ID`.

## Workflow

1. Resolve the task: `owl task current --json` (or use the supplied `TASK-ID`).
2. Choose a ready step: `owl task ready-steps TASK-ID --json` and take the requested or first ready entry; do not invent steps that are not in the ready set.
3. Mark the step started: `owl step start TASK-ID STEP-ID`.
4. Load the bundle: `owl step show TASK-ID STEP-ID --json`. Read `step`, `context`, `overlays`, `artifact_template`, `execution_mode`, and `task`.
5. Compose the working context (built-in `context` + overlays in returned order + relevant `task.artifacts` entries). Interpret it as the authoritative description of this step's purpose, acceptance criteria, and any step-specific hints.
6. Decide whether to prompt the user — apply the autonomous-by-default policy from the [conventions](../_owl_conventions.md):
   - `execution_mode == autonomous_after_brief` and `step.interactive != true` → proceed without prompting, except on real blockers.
   - `execution_mode == autonomous` → proceed without prompting, except on real blockers.
   - `execution_mode == interactive` or `step.interactive == true` → confirm with the user before producing the artifact.
   - When prompting, use the numbered-options form from the conventions.
7. If `artifact_template` is present:
   - Resolve the destination path: `owl artifact resolve TASK-ID ARTIFACT-KEY --json` (the `ARTIFACT-KEY` is in `step.creates`).
   - Generate Markdown body that covers every entry of `artifact_template.required_sections` and a YAML frontmatter matching `artifact_template.frontmatter_schema`.
   - Write the file at the resolved path. Do not invent paths; do not write outside `tasks/<TASK-ID>/`.
   - Validate: `owl artifact validate TASK-ID ARTIFACT-KEY --json`. If `ok` is false, read `errors`, fix the body, re-validate. Do not proceed until `ok: true`.
8. If the step has no artifact, execute the side effect described in `context` (for example, run the documented CLI subcommand, or perform the documented code change scoped to the task).
9. Complete the step: `owl step complete TASK-ID STEP-ID`. Owl re-runs the artifact validate gate here as a safety net.
10. Return control to the orchestrator (or to the human if invoked directly). Do not chain to the next step unless explicitly asked.

## Stop Conditions

Stop and report when:

- `owl task ready-steps` does not list the requested step (likely a dependency is incomplete).
- `owl step show` returns `unknown_step_id`, `task_workflow_missing`, or any other structured error.
- `context` is empty or absent and the step's purpose cannot be derived from `step.creates`, `overlays`, and `task.artifacts` alone — the workflow YAML is incomplete and the human needs to fill it.
- `owl artifact validate` reports errors that require product, scope, or data decisions the human must make.
- the requested artifact path is unsafe, points outside the task tree, or already exists with unrelated content.
- the step requires repository changes outside the current task's scope.
- a verification step returns `status: failed` for the second consecutive run on the same plan (real blocker per conventions).

## Verification

- Round-trip: after `owl step complete`, `owl status TASK-ID --json` shows the step `done` and the next step's `ready: true` flag flips correctly.
- Artifact path returned by `owl artifact resolve` exists on disk after the run.
- `owl artifact validate TASK-ID ARTIFACT-KEY --json` returns `ok: true` both before and after `owl step complete`.

## Notes

- The full `bin/owl` command surface, JSON response shapes, and error semantics are documented in the `owl-cli` skill. This skill assumes that reference is available; do not duplicate command tables here.
- This skill is intentionally generic: it does not switch behaviour on `STEP-ID` value. If you find yourself special-casing a particular step id, add the rule to that step's `context` in the workflow YAML, or add a project overlay at `.owl/overlays/<step>.md`, instead of branching here.
- Never read `.owl/`, `tasks/`, or `docs/` files directly to discover state — always go through `owl ...` CLI commands.
