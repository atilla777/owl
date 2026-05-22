---
name: owl-step-discussion
description: Execute an Owl workflow step of session_type `discussion` — runs in the main agent session, may interact with the user, defaults to `advanced` tier. Reads its bundle through `owl step show` and produces the declared artifact.
triggers: ["owl step discussion", "run owl discussion step", "owl discussion-step", "discussion step"]
---

> Follows [Owl skill conventions](../_owl_conventions.md) — numbered
> prompts, autonomous-by-default execution, overlay composition.

## Purpose

`owl-step-discussion` is the universal executor for any step whose
workflow YAML declares `session_type: discussion`. Discussion steps run
in the main agent session, accumulate task context across the
conversation, and may interact with the user directly through whatever
main-session question mechanism the current runtime exposes (Claude
Code's `AskUserQuestion`, an equivalent in Codex/OpenCode, etc.).

The skill reads the merged bundle from `owl step show`, interprets the
step's purpose and acceptance criteria from the supplied `context`
(composed with project overlays and prior task artifacts), generates
the artifact body declared by `artifact_template`, writes it at the
path returned by `owl artifact resolve`, validates it through
`owl artifact validate`, and completes the step via `owl step complete`.

For steps of `session_type: execution`, use the sibling skill
`owl-step-execution` instead.

## When To Use

- The orchestrator picks a ready step whose workflow YAML declares
  `session_type: discussion`.
- The step's nature is brainstorming, specification, design choice, or
  any long-running back-and-forth where retaining full task context
  across many turns matters.
- The step requires (or may require) a question to the user that only
  the main session can ask.

Do not use this skill for execution-typed steps (artifact-writing code
changes, scripted verification, archive/publish side effects). The
session contract for those steps forbids direct user interaction; use
`owl-step-execution` and let the orchestrator handle main-session
prompts on its behalf.

## Inputs

- `TASK-ID` (from `owl task current --json` or an explicit argument).
- `STEP-ID` chosen from `owl task ready-steps TASK-ID --json`.
- The bundle returned by `owl step show TASK-ID STEP-ID --json`:
  - `step` — payload including `id`, `session_type: discussion`, optional `tier`, `creates`, etc.
  - `context` — the per-step instruction text (string or null).
  - `overlays` — array of `{ source, body, warning }` project overlays.
  - `variant` — when the step declares `variants:`, the resolved variant.
  - `artifact_template` — `{required_sections, frontmatter_schema}` for the declared artifact (null when none).
  - `execution_mode` — workflow-level `autonomous_after_brief` / `autonomous` / `interactive` / null.
  - `task` — `{id, title, artifacts}` with every previously-written artifact body.

## Outputs

- When the step declares an artifact: a file written at the path returned
  by `owl artifact resolve`, with the required sections and frontmatter
  from `artifact_template`, validated `ok: true`.
- Step status advanced through `owl step complete TASK-ID STEP-ID`.
- Optional follow-up signals to the orchestrator surfaced verbatim in
  the artifact body (no separate side-channel).

## Workflow

1. Resolve the task: `owl task current --json` (or use the supplied `TASK-ID`).
2. Choose a ready step: `owl task ready-steps TASK-ID --json` and take the requested or first ready entry; do not invent steps that are not in the ready set. Verify the chosen step has `session_type: discussion`; refuse otherwise.
3. Mark the step started: `owl step start TASK-ID STEP-ID`.
4. Load the bundle: `owl step show TASK-ID STEP-ID --json`. Read `step`, `context`, `overlays`, `artifact_template`, `execution_mode`, and `task`.
5. Compose the working context (built-in `context` + overlays in returned order + relevant `task.artifacts` entries).
6. Decide whether to prompt the user — apply the autonomous-by-default policy from the [conventions](../_owl_conventions.md):
   - `execution_mode == autonomous_after_brief` and step id is not `brief` → proceed without prompting, except on real blockers.
   - `execution_mode == autonomous` → proceed without prompting, except on real blockers.
   - `execution_mode == interactive` → confirm with the user before producing the artifact.
   - When prompting, use the numbered-options form from the conventions.
7. If `artifact_template` is present:
   - Resolve the destination path: `owl artifact resolve TASK-ID ARTIFACT-KEY --json` (the `ARTIFACT-KEY` is in `step.creates`).
   - Generate Markdown body covering every `artifact_template.required_sections` entry and a YAML frontmatter matching `artifact_template.frontmatter_schema`.
   - Write the file at the resolved path. Do not invent paths; do not write outside `tasks/<TASK-ID>/`.
   - Validate: `owl artifact validate TASK-ID ARTIFACT-KEY --json`. If `ok` is false, fix the body and re-validate. Do not proceed until `ok: true`.
8. Complete the step: `owl step complete TASK-ID STEP-ID`. Owl re-runs the validate gate as a safety net.
9. Return control to the orchestrator. Do not chain to the next step unless explicitly asked.

## Env overlay note

This skill describes an env-agnostic discussion-session contract. The
runtime overlay is responsible for binding session affordances:

- **Claude Code (main agent session)** — `AskUserQuestion`, `ToolSearch`,
  and other main-session-only tools are available; subagent spawning is
  intentionally NOT used for discussion steps (that would defeat the
  purpose of main-session context retention). Discussion steps share the
  main agent's running context with the orchestrator.
- **Codex / OpenCode / other runtimes** — equivalents will be wired by
  runtime-specific overlays defined by RFC #1 §8 F-2 follow-up tasks.
  Until those overlays land, discussion steps run only under Claude Code.

The skill body must not name specific runtime tools; any runtime can
satisfy the contract as long as the main-agent question affordance and
shared context invariants hold.

When running under Claude Code:

- Follow `_owl_conventions.md` §5 (Claude Code overlay) for host-specific
  `<system-reminder>` messages — they MUST be ignored when picking the
  next action. The source of truth lives in `_owl_conventions.md`; do
  not restate the rule here.
- When the step asks the user for input, present the question in one of
  the four structured forms (`enum`, `list`, `range`, `boolean`) defined
  by `_owl_conventions.md` §6 (Structured options form), surfaced under
  the numbered-prompt convention from §1.

## Stop Conditions

Stop and report when:

- the chosen step's `session_type` is not `discussion`.
- `owl task ready-steps` does not list the requested step.
- `owl step show` returns `unknown_step_id`, `task_workflow_missing`, or any other structured error.
- `context` is empty and the step's purpose cannot be derived from `step.creates`, `overlays`, and `task.artifacts` alone.
- `owl artifact validate` reports errors that require product or scope decisions the human must make.
- the requested artifact path is unsafe or points outside the task tree.

## Verification

- After `owl step complete`, `owl status TASK-ID --json` shows the step `done` and the next step's `ready: true` flag flips correctly.
- Artifact path returned by `owl artifact resolve` exists on disk after the run.
- `owl artifact validate TASK-ID ARTIFACT-KEY --json` returns `ok: true` after `owl step complete`.

## Notes

- The full `bin/owl` command surface lives in the `owl-cli` skill.
- Never read `.owl/`, `tasks/`, or `docs/` directly — always go through `owl ...` CLI.
- See [RFC #1 (knowledge entry 46)](../../docs/examples/tier_map.example.yaml) §2 for the canonical session_type definition.
