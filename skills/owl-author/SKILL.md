---
name: owl-author
description: Universal Q&A authoring skill for Owl workflow definitions and artifact-type definitions. Creates new ones, edits existing ones, drives every change through `bin/owl workflow|artifact-type` CLI. Respects `settings.language.*`.
triggers: ["owl author", "owl-author", "author workflow", "author artifact", "create workflow", "create artifact-type", "edit workflow", "edit artifact-type", "new workflow", "new artifact-type"]
---

> Follows [Owl skill conventions](../_owl_conventions.md) — numbered
> prompts, autonomous-by-default execution.

# Skill: owl-author

## Purpose

`owl-author` is the agent-driven authoring surface for Owl workflow definitions (`.owl/workflows/<id>/workflow.yaml`) and artifact-type definitions (`.owl/artifacts/<id>/artifact.yaml`). It interviews the user through the harness Q&A surface (`AskUserQuestion`), drafts the resulting YAML body in memory, and persists every change through the `bin/owl workflow ...` / `bin/owl artifact-type ...` CLI. The skill never reads or writes those files directly — constitution 5.13 (skill layering) and 5.15 (Owl CLI as the only state interface).

The skill has three modes:

- **Mode A — Create workflow**: scaffold a new workflow definition and walk the user through filling in steps/artifacts.
- **Mode B — Create artifact-type**: scaffold a new artifact-type definition and walk the user through required_sections / front_matter / template body.
- **Mode C — Edit existing**: load a current definition via `owl workflow show` or `owl artifact-type show`, present its structure, gather a structured delta, and rewrite via `--force`.

## When To Use

- The user asks to "create a new workflow", "add a workflow for X", "design an artifact type for Y", "edit the feature workflow", "tweak the brief artifact", etc.
- The user supplies a rough sketch of a workflow (steps, artifacts) and wants the skill to formalize it into a valid YAML.

Do not use this skill for:

- editing task-scoped artifacts (use `owl-step-run` instead — those are per-task artifact files in `tasks/`).
- mid-stream renames of an existing definition that already has child tasks bound to it (out of scope for v1; flag as a separate task).
- configuring runtime settings (`settings.*`) — that's `owl-init` for bootstrap and `owl config set` for ongoing edits.

## Inputs

- Optional `mode: A|B|C` from the slash-command argument.
- Optional `target: workflow|artifact-type`.
- Optional `id` of the target definition.
- Live language preferences from `owl config show --json` (`settings.language.communication`, `settings.language.artifacts`).

## Outputs

- A new or rewritten `workflow.yaml` or `artifact.yaml` produced through `owl workflow new` / `owl artifact-type new` (optionally with `--force` for edits).
- A passing `owl workflow validate` / `owl artifact-type validate` confirming the result.
- A short user-facing summary in `settings.language.communication`.

## Workflow

1. **Pre-flight**: confirm project root and language settings.
   - `owl config show --root . --json` → capture `settings.language.communication` and `settings.language.artifacts` (defaults: `communication` for both).
   - If the user did not supply `mode`/`target`/`id`, ask once: "What do you want to do — create workflow / create artifact-type / edit existing?"

2. **Mode selection**: dispatch to one of the three workflows below.

### Mode A — Create workflow

1. **Q1 — `id`**: ask for the new workflow id (lowercase snake_case). Refuse anything that does not match `/^[a-z][a-z0-9_]*$/`.
2. **Q2 — `kind`**: ask `task | composite_task` (default: `task`).
3. **Q3 — `title`**: ask for a human-readable title (in `settings.language.artifacts`).
4. **Q4 — `description`**: ask for a one-paragraph description (in `settings.language.artifacts`).
5. **Q5 — artifacts**: iterative loop. For each artifact: ask `key`, `type` (must exist in `owl artifact-type list` results — if not, suggest running Mode B first), and `storage.path` (default: `{{task.id}}/<key>.md`). Stop the loop when the user says "no more".
6. **Q6 — steps**: iterative loop. For each step: ask `id`, optional `requires` (comma-separated list of earlier step ids), optional `creates` (comma-separated list of artifact keys declared above), optional `context_file` (default: `<step_id>.context.md`). The skill auto-fills `skill: owl-step-run` for every step unless the user names a different `owl-step-<x>` skill explicitly.
7. **Q7 — confirm**: show the assembled YAML and ask for confirmation.
8. **Persist**: pipe the body into `owl workflow new --id <id> --kind <kind> --body -`. On success, run `owl workflow validate <id-or-path> --json`. On `ok: true`, summarize for the user; on failure, surface errors and ask whether to fix interactively (loop back to the relevant Q) or abort.
9. **Registry reminder**: print "To enable this workflow project-wide, add it to `.owl/workflows.yaml` (see existing entries)."

### Mode B — Create artifact-type

1. **Q1 — `id`**: ask for the new artifact-type id (lowercase snake_case). Refuse anything that does not match `/^[a-z][a-z0-9_]*$/`.
2. **Q2 — `title`**: ask for a human-readable title (in `settings.language.artifacts`).
3. **Q3 — `kind`**: ask for the kind (default: `markdown`).
4. **Q4 — `description`**: one-paragraph description (in `settings.language.artifacts`).
5. **Q5 — `required_sections`** (constitution 5.16: always English): iterative loop. For each section: ask the English heading text. Reject any input that contains characters outside `[A-Za-z0-9 _\-]` with an explicit message: "required_sections are part of schema identity and must stay English per constitution 5.16."
6. **Q6 — `front_matter`**: ask which keys are required (default: `status`, `summary`). For each key ask `type` (string/object/array/boolean/integer/null) and optional `enum`.
7. **Q7 — `template.body`**: ask for the default template body. The body is written in `settings.language.artifacts`. Headings inside the body should mirror `required_sections` (English) for byte-for-byte validation.
8. **Q8 — confirm**: show the assembled YAML and ask for confirmation.
9. **Persist**: pipe the body into `owl artifact-type new --id <id> --body -`. The CLI auto-seeds a minimal `templates/default.md` next to the new `artifact.yaml`. If the user supplied a custom template body in Q7, write it via `owl artifact-type template set <id> --body -` (use `--template <name>` for additional templates). Validate it with `owl artifact-type template validate <id>`. To make the type project-wide, add `--register` to `new`, or run `owl artifact-type register <id>` (project-owned, `managed: false`). To start from an existing type, clone with `owl artifact-type new --from <base> --id <new>`. Managed (Owl-shipped) types are read-only: `template set` refuses them — clone first.
10. **Validate**: `owl artifact-type validate <id-or-path> --json`. On `ok: true`, summarize; on failure, surface errors.

### Mode C — Edit existing

1. **Target**: confirm `target` (`workflow|artifact-type`) and `id`.
2. **Load**: run `owl <target> show <id> --json`. Parse the `definition` block.
3. **Present**: show the user a structured overview — for workflows, list `id / kind / title / description / artifacts / steps`; for artifact-types, list `id / title / kind / description / required_sections / front_matter`.
4. **Delta Q&A**: ask per section "change this? [y/N]". For each `y`, run the matching Mode A or Mode B question(s) and capture the new value.
5. **Re-assemble**: produce the new full YAML in memory by applying the delta to the parsed body.
6. **Persist**: pipe the body into `owl <target> new --id <id> --body - --force` (the `--force` flag is required for overwriting).
7. **Validate**: `owl <target> validate <id-or-path> --json`. On `ok: true`, summarize; on failure, surface errors and offer to fix interactively (loop back to the relevant Q) or abort.

## Language Clause (constitution 5.16, 5.17)

- SKILL.md body is **English** (canonical contract; constitution 5.16).
- Harness Q&A prompts and the final summary are in `settings.language.communication` (read from `owl config show --json` at the start of every run). If `settings.language.communication` is missing, fall back to English and remind the user to run `owl-init`.
- YAML content the skill drafts (titles, descriptions, template body) is written in `settings.language.artifacts` (defaults to `communication` when missing).
- `required_sections` literal headings inside artifact-type YAMLs are **always English** — the skill validates the user's input against `[A-Za-z0-9 _\-]` and rejects localized strings with an explicit constitution-5.16 reference.

## Stop Conditions

Stop and return control to the user with a concrete decision request when:

- the project root cannot be detected (no `.owl/`).
- `owl config show` is missing required language settings — direct the user to `owl-init`.
- the user supplies an `id` that already exists and Mode A/B is requested without explicit "overwrite" intent — ask whether to switch to Mode C or pick a different id.
- the `type` field of a workflow artifact references an unknown artifact-type — ask whether to switch into Mode B and create it first, or use a different type.
- `owl workflow validate` / `owl artifact-type validate` fails twice in a row on the same set of errors — surface the errors and ask the user to fix manually or abort.
- the user provides a localized string for `required_sections` and refuses to convert it to English — abort with an explicit constitution-5.16 reference.
- `owl workflow new` / `owl artifact-type new` returns a structured error (`invalid_workflow_id`, `workflow_already_exists`, `workflow_validation_failed`, `artifact_type_already_exists`, `artifact_type_validation_failed`) the skill cannot resolve through one obvious retry.

## Verification

- After a complete Mode A run, `owl workflow validate <id-or-path> --json` returns `{ok: true, valid: true, errors: []}`.
- After a complete Mode B run, `owl artifact-type validate <id-or-path> --json` returns the same.
- After a complete Mode C run, the rewritten definition validates AND `owl <target> show <id> --json` reflects the new content.
- The skill never reads or writes `.owl/workflows/*` or `.owl/artifacts/*` files directly; every state-changing operation goes through `bin/owl`.

## Notes

- `owl workflow new` / `owl artifact-type new` accept the YAML body via `--body -` (stdin). The skill assembles the YAML in memory and pipes it in — there is no granular `set-step` / `set-section` CLI; the new/--force pattern is the contract.
- `owl workflow new --kind composite_task` seeds with a one-step `decompose` baseline; Mode A typically expands it through Q6 into a full multi-step composite workflow.
- For `--from` cloning (e.g. "make a new workflow from feature"), use `owl workflow new --id <new-id> --from feature`. The skill may offer this as a shortcut when the user says "start from <existing>".
- Validate-by-path vs validate-by-id: when a new workflow is not yet registered in `.owl/workflows.yaml`, only `owl workflow validate .owl/workflows/<id>/workflow.yaml` works. The skill uses the source path from the `new` response to validate freshly scaffolded definitions.
- Registry inclusion is via CLI, not manual edits: `new` deliberately does not register (so ad-hoc experiments do not pollute the registry), but `owl workflow|artifact-type register <id>` (or `new --register`) adds the entry as project-owned (`managed: false`), and `unregister` removes it. Seeded/Owl-shipped definitions are `managed: true` (read-only, upgrade-safe); customize by cloning with `--from`, then editing the copy.
- Step context files and workflow bodies round-trip via CLI too: `owl workflow source show <id>` (raw YAML), `owl workflow context show|set <id> <step> [--variant V]`. `context set` refuses managed workflows.
