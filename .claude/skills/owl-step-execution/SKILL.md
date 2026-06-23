---
name: owl-step-execution
description: Execute an Owl workflow step of session_type `execution` — runs in an isolated subagent session, never interacts with the user directly, defaults to `standard` tier. Reads its bundle through `owl step show`, produces the declared artifact, and emits a structured report via `owl step report --body -`.
triggers: ["owl step execution", "run owl execution step", "owl execution-step", "execution step"]
---

> Follows [Owl skill conventions](../_owl_conventions.md) — overlay
> composition, no direct user interaction.

## Purpose

`owl-step-execution` is the universal executor for any step whose
workflow YAML declares `session_type: execution`. Execution steps run
in an isolated subagent session (or main-session equivalent when no
spawn mechanism exists yet) with a context window limited to the
input bundle and no direct line to the user. The output is a structured
report — markdown-with-frontmatter — written through `owl step report
--body -` so the orchestrator can read it back regardless of the
underlying runtime.

For steps of `session_type: discussion`, use the sibling skill
`owl-step-discussion`.

## When To Use

- The orchestrator picks a ready step whose workflow YAML declares
  `session_type: execution` (artifact writes, scripted verification,
  archive, publish, commit, anything mechanical).
- The step's behaviour does not require live back-and-forth with the
  user.

Do not use this skill to brainstorm, design, or make scope decisions.
Those belong to `owl-step-discussion`.

## Inputs

- `TASK-ID` and `STEP-ID` passed in the spawn bundle (do not call
  `owl task current` to re-derive them; they are authoritative inputs).
- Bundle from `owl step show TASK-ID STEP-ID --json` with the same
  fields documented in `owl-step-discussion`. The `step.session_type`
  field must equal `"execution"`; abort otherwise.

## Outputs

- When the step declares an artifact: a file at the path returned by
  `owl artifact resolve`, validated `ok: true` by `owl artifact validate`.
- A structured report saved through:
  ```
  owl step report --task-id TASK-ID --step-id STEP-ID --body -
  ```
  The body is markdown-with-frontmatter (RFC #1 §4.3):
  ```
  ---
  status: returned_normally|do_not_use|error
  summary: "<one-line>"
  session_type: execution
  ---

  ## Result

  <what was produced; pointers to artifacts and CLI commands invoked>

  ## Tool usage

  <optional: tools invoked, in order>

  ## Open follow-ups

  <optional: questions the orchestrator should ask the user>
  ```
- Step status advanced through `owl step complete TASK-ID STEP-ID`.

## Workflow

1. Verify the step is in scope: parse the input bundle, ensure `step.session_type == "execution"`. Abort with `final_state: error` if not.
2. Mark the step started: `owl step start TASK-ID STEP-ID`.
3. Compose the working context strictly from the supplied bundle: built-in `context` + overlays in returned order + `task.artifacts`. Do not call discovery tools that read filesystem state outside `bin/owl`.
4. NEVER prompt the user directly. If the step needs human input to proceed, finalize with `final_state: interrupted` and surface the question in the `## Open follow-ups` section of the report. The orchestrator will then ask the user from the main session.
5. If `artifact_template` is present:
   - Resolve the destination path: `owl artifact resolve TASK-ID ARTIFACT-KEY --json`.
   - Generate Markdown body covering every `artifact_template.required_sections` entry and frontmatter matching `artifact_template.frontmatter_schema`.
   - Write the file. Do not invent paths.
   - Validate: `owl artifact validate TASK-ID ARTIFACT-KEY --json`. Loop fix-validate until `ok: true`.
6. If the step has no artifact (e.g., `archive`, `commit_push`, `publish`, `merge_docs`): execute the side effect described in `context` (typically a `bin/owl ...` subcommand). For `commit_push`, that side effect is a single transactional command — `owl commit-push TASK-ID --message "Owl: <subject>"` — which stages, flips `commit_push: done`, commits, pulls --rebase and pushes under the `git` lock in one operation; it self-completes the step, so step 7's `owl step complete` is a harmless idempotent no-op for it. Run the overlay's preconditions (`git status` review, push target) before the command; on `push_retryable` re-run the same command to retry the push without a second commit.
7. Complete the step: `owl step complete TASK-ID STEP-ID`.
8. Compose the report body (markdown-with-frontmatter as above) and write it through `owl step report --task-id TASK-ID --step-id STEP-ID --body - --validate`. Validation must pass before the session ends.
9. Return.

## Env overlay note

This skill describes an env-agnostic execution-session contract. The
runtime overlay decides how the subagent is actually spawned:

- **Claude Code** — the orchestrator invokes this skill via the Task
  tool with an appropriate `subagent_type`; the subagent runs in an
  isolated context and uses `owl step report --body -` to hand back its
  output. The subagent must not call `AskUserQuestion` or
  `ToolSearch`-driven discovery — those are main-session affordances
  and using them from a subagent has been verified as
  `do-not-use` (see RFC #1 §6 experiment).
- **Codex / OpenCode / other runtimes** — runtime-specific overlays
  bind this skill to whatever spawn mechanism exists. The contract is
  unchanged.
- **Fallback (no overlay yet)** — when no runtime overlay is wired, the
  orchestrator may execute this skill in the main session as a
  best-effort fallback; the autonomy and no-user-interaction rules
  still apply.

## Stop Conditions

Finalize with `final_state: interrupted` and surface the issue in the
report's `## Open follow-ups` section when:

- the step needs human input to proceed (scope, ambiguity, validation failure that requires product judgement).
- `owl artifact validate` fails twice consecutively on the same plan.
- the step requires repository changes outside the current task's scope.
- a verification side effect returns a non-zero exit on the second run.

Finalize with `final_state: error` and explain in `error_message` when:

- the chosen step's `session_type` is not `execution`.
- `owl task ready-steps` does not list the requested step.
- `owl step show` returns a structured error that cannot be retried.

In either case, the orchestrator reads the report through `owl step
report --read` and decides next action.

## Verification

- After `owl step complete`, `owl status TASK-ID --json` shows the step `done`.
- `owl step report --task-id ... --step-id ... --read` returns the
  report body the orchestrator can consume.
- The report body parses through the default output_spec
  (`Owl::Subagents::Internal::OutputSpec`).

## Notes

- The full `bin/owl` command surface lives in the `owl-cli` skill.
- **Language Clause (Owl Constitution 5.16/5.17, `_owl_conventions.md` §7).** Although this session never talks to the user directly, its report prose that the orchestrator surfaces to the human — `summary` and any `## Open follow-ups` questions — must be written in `settings.language.communication` (from the `owl step show` bundle or `owl config show --json`). Write the artifact *body* in `settings.language.artifacts` (default = `communication`); keep `required_sections` headings, frontmatter keys, and the report's `status` field English (schema identity).
- **Never read or mutate Owl state files directly** (`.owl/`, `tasks/`, `docs/`) — always go through `owl ...`. The one sanctioned write into `tasks/<TASK-ID>/` is the artifact body, and **only** at the exact path returned by `owl artifact resolve`, followed by `owl artifact validate`. Do not hand-edit `task.yaml`, step state, or any other file under those trees.
- See RFC #1 (knowledge entry 46) §§2, 4 for the canonical session_type and spawn_subagent contract definitions.
