---
name: owl-orchestrator
description: Drive an Owl task through its workflow end-to-end. Read state through the `owl` CLI, dispatch each ready step by its `session_type` (`discussion` → main session via `owl-step-discussion`; `execution` → subagent via `owl-step-execution`), stop on real human decisions.
triggers: ["owl orchestrator", "continue owl task", "drive owl workflow", "next owl step"]
---

> Follows [Owl skill conventions](../_owl_conventions.md) — numbered
> prompts, autonomous-by-default execution.

## Purpose

Drive an Owl task from its current ready step to the workflow's terminal step using the `owl` CLI as the sole source of truth. Each step in a session-typed workflow declares `session_type: discussion` or `session_type: execution` (RFC #1 §2, knowledge entry 46); the orchestrator dispatches to `owl-step-discussion` (main session) or `owl-step-execution` (subagent) accordingly. Custom workflows may name their own `owl-step-<x>` skill and the orchestrator delegates verbatim through `owl instructions`.

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
5. Resolve the bound skill: `owl instructions TASK-ID --step-id STEP --json` returns the step invocation packaged with the matching `SKILL.md` path, slash-command path, and a one-paragraph summary. For seeded workflows the binding is `owl-step-discussion` or `owl-step-execution` depending on the step's `session_type`; custom workflows may name their own skill and the orchestrator delegates verbatim. Use `owl step invocation TASK-ID STEP --json` when only the raw invocation block is needed.
6. Dispatch by `session_type` (read from the bundle returned by `owl step show TASK-ID STEP --json`):
   - `session_type: discussion` → invoke the bound skill (typically `owl-step-discussion`) in the main agent session so it can use main-session-only affordances (e.g. `AskUserQuestion` in Claude Code) and retain conversation context across turns.
   - `session_type: execution` → spawn a subagent through the runtime's mechanism (in Claude Code: the Task tool with `subagent_type: general-purpose` or equivalent) and let the subagent run the bound skill (typically `owl-step-execution`). Pass `TASK-ID` and `STEP-ID`; the subagent reads its bundle through `owl step show` and emits its report via `owl step report --task-id TASK-ID --step-id STEP-ID --body -`. The orchestrator then reads the report through `owl step report --task-id TASK-ID --step-id STEP-ID --read` and inspects its `## Open follow-ups` section for any questions the subagent cannot answer itself.
   - When no runtime overlay for subagent spawning is wired yet, the orchestrator may fall back to executing an `execution` step inline in the main session — the contract still forbids direct user interaction and still requires the structured report.
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
- a `composite_feature` parent reaches its `review` or `archive` step while child tasks are still in progress (`owl task aggregate-status PARENT-ID --json` reports unready children, or `owl archive PARENT-ID` returns `composite_with_unready_children`);
- `owl publish` or `owl archive` would overwrite content that does not look like a `.backup-<timestamp>` candidate or that lives outside the current task tree;
- the `owl` CLI returns a structured error (`task_workflow_missing`, `unknown_step_id`, `step_not_ready`, `composite_with_unready_children`, etc.) that the orchestrator cannot resolve through one obvious retry.

When stopping, report the active `TASK-ID`, the step that failed or blocked progress, the `owl ...` command output, and one explicit question for the human.

## Notes

- `owl step skip TASK-ID STEP --reason "..."` is allowed only for steps the workflow YAML marks optional. Do not skip required steps to make progress — fix the underlying issue or stop.
- For `composite_feature` tasks the seeded workflow is `brief → design? → decompose → review → archive → commit_push`. `decompose` spawns child tasks; the parent's `review` step rolls up child status; `archive` runs atomically over the full subtree. Use `owl task tree TASK-ID --json` / `owl task children PARENT-ID --json` / `owl task aggregate-status PARENT-ID --json` to inspect the subtree. `owl archive PARENT-ID --json` archives the full subtree atomically — if any child is unready, it returns `composite_with_unready_children` rather than partial archive.
- The full `bin/owl` command surface, JSON response shapes, and error semantics are documented in the `owl-cli` skill — consult that reference rather than parsing `owl --help`.
- In the session-typed model, each seeded step's `skill:` binding resolves to `owl-step-discussion` (for `session_type: discussion`) or `owl-step-execution` (for `session_type: execution`). Both overlays read per-step `context` from `owl step show` and produce the declared artifact without hardcoded step-type knowledge. The orchestrator's job is to pick the step, dispatch by session_type, and trust the binding.
- Never read `.owl/`, `tasks/`, or `docs/` files directly. Always go through `owl ...` CLI. This is an architectural invariant of Owl.
