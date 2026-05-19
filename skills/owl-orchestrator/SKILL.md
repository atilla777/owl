---
name: owl-orchestrator
description: Drive an Owl task through its workflow end-to-end. Read state through the `owl` CLI, delegate each ready step to the universal `owl-step-run` skill, stop on real human decisions.
triggers: ["owl orchestrator", "continue owl task", "drive owl workflow", "next owl step"]
---

> Follows [Owl skill conventions](../_owl_conventions.md) — numbered
> prompts, autonomous-by-default execution.

## Purpose

Drive an Owl task from its current ready step to the workflow's terminal step using the `owl` CLI as the sole source of truth. Every seeded step binds the universal `owl-step-run` skill; the orchestrator's job is to pick the next ready step and trust that binding. The orchestrator stays skill-binding-agnostic so a custom workflow that names a different skill still resolves through `owl instructions`.

## When To Use

- The user has a current Owl task and asks to continue, do the next step, or names a specific `TASK-ID`.
- A new task was just created and is ready for its first step.
- A previous orchestrator run was interrupted and needs to resume from the current ready step.

Do not use this skill to invent workflow stages, edit `.owl/` config, or run product/scope decisions on behalf of the human.

## Inputs

- Current `TASK-ID` from `owl task current --json` or an explicit `TASK-XXXX` argument.
- Optional `STEP-ID` when the human names one explicitly; otherwise pick the first entry from `owl task ready-steps TASK-ID --json`.

## Outputs

- Each step's artifact (when the step declares one) written through the executor skill at the path returned by `owl artifact resolve` and validated `ok: true` by `owl artifact validate`.
- Step status advanced through `owl step start` / `owl step complete` / `owl step skip` — owl re-runs the validate gate at `complete` time.
- Workflow-terminal effects when the workflow declares them (typically `owl publish` and `owl archive`).
- A short human-facing summary at end of run, or a stop report when human input is required.

## Workflow

1. Resolve the active task: `owl task current --json`. If the user named a different task, switch with `owl task use TASK-ID`.
2. Inspect progress: `owl status TASK-ID --json` returns the agent-friendly summary (steps with `ready` flag, `progress {done, total, pct}`, blockers, `children` for composite tasks). Fall back to `owl task inspect TASK-ID --json` only when the raw `task.yaml` payload is needed.
3. Optional diagram chunk: if `owl config get settings.ui.auto_render_diagram --json` returns `true`, execute `bin/owl workflow show TASK-ID` and print the stdout as a single user-visible chunk before picking the next step. Render the diagram at most once per loop iteration. When the key is unset or `false`, skip this step.
4. Pick the next ready step: `owl task ready-steps TASK-ID --json`. Take the first entry unless the user named one. Do not invent a step id that is not in the ready set.
5. Resolve the bound skill: `owl instructions TASK-ID --step-id STEP --json` returns the step invocation packaged with the matching `SKILL.md` path, slash-command path, and a one-paragraph summary. For seeded workflows the binding is always `owl-step-run`; a custom workflow can name its own skill and the orchestrator delegates verbatim. Use `owl step invocation TASK-ID STEP --json` when only the raw invocation block is needed.
6. Delegate execution to the bound skill. It is responsible for `owl step start`, generating the artifact (when one is declared), and producing valid output. Pass the `TASK-ID` and `STEP-ID` to the delegated skill; do not paste step-specific instructions inline.
7. After delegation returns:
   - Re-validate the artifact: `owl artifact validate TASK-ID ARTIFACT-KEY --json` returns `{ok, errors}`. Inspect `ok` before assuming success.
   - Mark the step complete: `owl step complete TASK-ID STEP-ID`. Owl re-runs the validate gate at complete time as a safety net.
8. Loop from step 2 until `owl task ready-steps` returns empty AND the workflow's terminal step (typically `archive`) is done. Stop and report when no more progress is possible.

## Stop Conditions

Stop and return control to the human with a concrete decision request when:

- artifact validation fails twice in a row on the same step and the second pass would require a product, scope, or data decision;
- `owl task ready-steps` returns empty but the workflow's terminal step is not done (the workflow graph has an unsatisfied dependency the human must unblock);
- `git status` shows suspicious or unrelated files in the working tree, making the step's scope ambiguous;
- the delegated step skill returns its own stop condition (e.g., `owl-step-run` could not infer the step's purpose from the supplied `context`);
- a `composite_feature` parent reaches `aggregate_verify` while child tasks are still in progress (`owl task aggregate-status PARENT-ID --json` reports unready children);
- `owl publish` or `owl archive` would overwrite content that does not look like a `.backup-<timestamp>` candidate or that lives outside the current task tree;
- the `owl` CLI returns a structured error (`task_workflow_missing`, `unknown_step_id`, `step_not_ready`, `composite_with_unready_children`, etc.) that the orchestrator cannot resolve through one obvious retry.

When stopping, report the active `TASK-ID`, the step that failed or blocked progress, the `owl ...` command output, and one explicit question for the human.

## Notes

- `owl step skip TASK-ID STEP --reason "..."` is allowed only for steps the workflow YAML marks optional. Do not skip required steps to make progress — fix the underlying issue or stop.
- For `composite_feature` tasks: `decompose` spawns child tasks; `coordinate` tracks them; `aggregate_verify` rolls up child verification reports. Use `owl task tree TASK-ID --json` / `owl task children PARENT-ID --json` / `owl task aggregate-status PARENT-ID --json` to inspect the subtree. `owl archive PARENT-ID --json` archives the full subtree atomically — if any child is unready, it returns `composite_with_unready_children` rather than partial archive.
- The full `bin/owl` command surface, JSON response shapes, and error semantics are documented in the `owl-cli` skill — consult that reference rather than parsing `owl --help`.
- In the universal-step model, every seeded step's `skill:` binding resolves to `owl-step-run`; that skill reads per-step `context` from `owl step show` and produces the declared artifact without hardcoded step-type knowledge. The orchestrator's job is to pick the step and trust the binding.
- Never read `.owl/`, `tasks/`, or `docs/` files directly. Always go through `owl ...` CLI. This is an architectural invariant of Owl.
