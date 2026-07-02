---
name: owl-init
description: First-run wizard that interviews the user for Owl runtime settings (language, storage, optional workflows) and writes them to `.owl/config.yaml` via `owl config set`. One-shot bootstrap — not for mid-project re-config.
triggers: ["owl init", "owl-init", "initialize owl", "owl wizard", "owl first run", "configure owl"]
---

> Follows [Owl skill conventions](../_owl_conventions.md) — numbered
> prompts, autonomous-by-default execution.

# Skill: owl-init

## Purpose

`owl-init` is the agent-driven first-run wizard for a fresh Owl project. It asks the user a small fixed set of questions through the harness Q&A surface (`AskUserQuestion`), records each answer through `owl config set settings.* VALUE`, and runs a final `owl config validate --json` to confirm the new config is healthy.

The wizard is the **only** sanctioned UX for creating the initial `settings:` block of `.owl/config.yaml`. CLI surface for runtime modification is `bin/owl config get|set|show` (documented in `owl-cli`); this skill is the **one-shot bootstrap** that fills the block in the first place.

## When To Use

`owl init` already seeds a **fully working** `.owl/config.yaml` with
sensible defaults (`settings.language.communication: en`, filesystem
storage, both seeded workflows registered). This wizard is therefore
**not a prerequisite for using Owl** — it is an optional customization
step. Use it when:

- The user has explicitly asked to "initialize / configure owl", "run
  the owl wizard", or pick non-default language / storage paths.
- The user wants to filter the enabled-workflow list via
  `settings.workflows.enabled` (the seeded empty list `[]` means
  *allow all*, not *block all*; the real workflow registration is in
  `.owl/workflows.yaml`).

**Skip this wizard** when the user only asked to install Owl and has
not requested customization — proceed directly to first-task creation
(`Skill(skill: "owl-task-create")` or `owl task create --workflow
feature --title "..."`). Confirm in one sentence that defaults are in
place; do not stop the install asking the user to type `/owl-init`.

This skill is **agent-invokable**: the agent loads it through the
harness `Skill` tool and uses `AskUserQuestion` to collect user
answers in-chat. The `/owl-init` slash command is the equivalent
human-typing handle for the same skill; never tell the user "you must
type this" — invoke the skill yourself when the wizard is appropriate.

Do not use this skill to:

- **mid-project re-config**: the wizard refuses if `settings.language.communication` is already set unless the user explicitly confirms re-configuration. For ongoing edits, use `bin/owl config set settings.* VALUE` directly or delegate to `owl-author` for workflow/artifact edits.
- run product/scope decisions on behalf of the user.
- edit anything outside `settings.*` — top-level `project:`, `workflow:`, and legacy `storage:` blocks are not part of this skill's surface.

## Inputs

- Repository root with a `.owl/config.yaml` produced by `owl init` (or the wizard runs `owl init` first when the file is missing).
- User answers through harness Q&A (`AskUserQuestion`) — seven questions total, several with sensible defaults so the user can accept the whole flow with just confirmations.

## Outputs

- `.owl/config.yaml` `settings:` block populated with the user's choices:
  - `settings.language.communication` (required)
  - `settings.language.artifacts` (inherits from communication or user override)
  - `settings.language.docs` (inherits from communication or user override)
  - `settings.storage.backend` (`filesystem` in v1)
  - `settings.storage.roles.tasks|docs|archive` (defaults shown; per-role override on opt-in)
  - `settings.workflows.enabled` (optional list)
  - `settings.plan_approval.required` (optional boolean, default absent/`false`; when `true`, every new plan-bearing task holds `implement` at `await_plan_approval` until `owl plan approve`)
  - `settings.ui.auto_render_diagram` (optional boolean, default `false`; when `true`, `owl-orchestrator` prints a workflow diagram once per loop iteration via `bin/owl workflow show TASK-ID`)
  - `settings.ui.auto_render_tree` (optional boolean, default `false`; when `true`, `owl-orchestrator` prints a task-tree overview via `bin/owl overview` once at the start of a drive and on each composite handoff)
- A short user-facing summary report in `settings.language.communication` describing what was recorded.

## Workflow

1. **Pre-flight**: confirm `bin/owl` is reachable and a project root exists.
   - Run `owl config show --root . --json`. If it returns `config_missing`, run `owl init --root .` first.
   - Run `owl config get settings.language.communication --root . --json`. If the call succeeds (key already set), ask the user: "Settings are already configured (communication=<value>). Re-run wizard?" If the user declines, exit no-op with a summary.

2. **Q1 — communication language (required, no default)**:
   - English-language prompt: "Which language should agents use for user-facing communication? (e.g. en, ru, es)"
   - Persist: `owl config set settings.language.communication <answer>`.

3. **Q2 — artifacts language (default = communication)**:
   - Localized prompt in `<communication>` language: "Same language for artifacts as for communication? [Y/n]"
   - If Y: `owl config set settings.language.artifacts <communication_value>`.
   - If n: ask for the value, then `owl config set settings.language.artifacts <answer>`.

4. **Q3 — docs language (default = communication)**: same shape as Q2.
   - If Y: `owl config set settings.language.docs <communication_value>`.
   - If n: ask for the value, then `owl config set settings.language.docs <answer>`.

5. **Q4 — storage backend**: `filesystem` is the only supported v1 backend; record it without prompting: `owl config set settings.storage.backend filesystem`.

6. **Q5 — storage role paths**:
   - Show the defaults table to the user (`tasks → ./tasks`, `docs → ./docs`, `archive → ./tasks/archive`).
   - Ask: "Accept default storage role paths? [Y/n]"
   - On Y: no per-role prompts (defaults are already in the config from `owl init`).
   - On n: ask per role and run `owl config set settings.storage.roles.<role> <answer>` for each override.

7. **Q6 — workflows enable list (optional)**:
   - Show a multi-select of `owl workflow list --json` results.
   - Ask: "Which workflows do you want enabled? (leave empty to allow all)"
   - On selection: `owl config set settings.workflows.enabled '["..."]'` (JSON array literal).
   - Empty selection: `owl config set settings.workflows.enabled '[]'` (explicit empty list).

8. **Q7 — plan-approval checkpoint (optional, default off)**:
   - Ask: "Require human plan approval before the implement step by default? Owl will pause each plan-bearing task (`feature`/`hotfix`/`refactor`) at `await_plan_approval` until you run `owl plan approve`. [y/N]"
   - On Y: `owl config set settings.plan_approval.required true`.
   - On N (default): record nothing (an absent key means not required); mention that any single task can still opt in per-run with `owl task create ... --require-plan-approval`.

9. **Final validation**:
   - Run `owl config validate --root . --json`.
   - On `ok: true`: print a localized summary of the recorded settings.
   - On `ok: false`: report the validation errors and stop; the user must fix manually via `owl config set` or restart the wizard.

## Language Clause (constitution 5.16, 5.17)

- SKILL.md content is English (canonical contract; constitution 5.16).
- **Before Q1 is answered**, the wizard speaks **English** to the user: the communication language is not yet known.
- **After Q1**: the wizard switches to `settings.language.communication` for all subsequent prompts, status messages, and the final summary.
- Downstream Owl skills (`owl-orchestrator`, `owl-step-discussion`, `owl-step-execution`) read `settings.language.communication` through `owl step show --json` or `owl config show --json` and respect it for their own user-facing reports.
- `required_sections` literal headings in artifact templates remain English regardless of `settings.language.artifacts` (template identity is part of schema validation).

## Stop Conditions

Stop and return control to the user with a concrete decision request when:

- `bin/owl` is not on PATH, or `owl init` fails (cannot create `.owl/`).
- `owl config show` reports `config_missing` and `owl init` cannot be run safely (existing files in the way).
- the user declines re-configuration on an already-initialized project — exit no-op with a summary; do not silently overwrite.
- `owl config set` returns a structured error (`config_validation_failed`, `invalid_config_value`, `invalid_config_key`) — surface the message and ask the user how to proceed.
- `owl config validate` after wizard completion reports `valid: false` — show the errors and stop.
- the user provides ambiguous input that cannot be normalized to a stable string or JSON literal (for the workflows list).

## Verification

- After a complete wizard run on a freshly initialized project, `owl config validate --root . --json` returns `{ok: true, valid: true, errors: []}`.
- `owl config get settings.language.communication --root . --json` returns the user-chosen value.
- `owl config show --root . --json` reflects the full set of recorded `settings.*` keys.

## Notes

- The wizard never reads or writes `.owl/config.yaml` directly. All persistence flows through `owl config set` (constitution 5.15: "Owl CLI as the only state interface").
- JSON-array literal syntax for `owl config set`: pass single-quoted JSON, e.g. `owl config set settings.workflows.enabled '["feature","bugfix"]'`. The empty list is `'[]'`.
- The wizard is intentionally minimal. New `settings.*` fields are added by extending this skill's Q&A and the validator schema, not by inventing a new CLI subcommand.
- This skill is one-shot. For changing a single setting later, use `bin/owl config set settings.<path> <value>` (see `owl-cli`).
