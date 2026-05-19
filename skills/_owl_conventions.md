---
name: _owl_conventions
description: Shared conventions every Owl-shipped skill follows — numbered prompts, autonomous-by-default policy. Not a standalone skill; referenced by other skills.
---

# Owl skill conventions

This document captures behavioural rules that apply to every
Owl-shipped skill (`owl-author`, `owl-cli`, `owl-init`,
`owl-orchestrator`, `owl-step-run`). Skills reference this file rather
than restating these rules.

## 1. Numbered prompts

When a skill needs the user's input, it MUST present options as a
numbered list so the user can answer with a digit:

```
<Question>?
1. <Option A>
2. <Option B>
3. <Option C>
```

Confirmations also use the numbered form:

```
Proceed? 1. yes  2. no
```

Accept any of: the digit (`1`), the option text (`yes`), or a free-text
answer (treat as "other"). When using `AskUserQuestion`, the question
text and option labels should still surface the digits so the user can
respond by number in the chat.

## 2. Autonomous-by-default execution

Workflows declare an `execution_mode` at the top level and an optional
`interactive: true` flag on each step. Skills MUST honor both:

| `execution_mode`            | Default step behavior              |
| --------------------------- | ---------------------------------- |
| `autonomous_after_brief`    | Run without prompting the user, except for steps with `interactive: true` and except on real blockers. |
| `autonomous`                | Run without prompting the user, except on real blockers. |
| `interactive`               | Confirm with the user before each step. |
| (absent)                    | Treat as `interactive` for backward compatibility. |

A "real blocker" is one of:

- Ambiguity in the user's input that affects scope or correctness.
- A validation failure (`owl ... validate` returns `ok: false`) that
  needs product/scope judgement.
- An irreversible action (push to a shared remote, deletion of files
  outside the task tree, schema migration).
- Verification status `failed` for the second consecutive run on the
  same plan.

Anything else — running tests, fixing lint, retrying a failed
validation, choosing between mechanically-equivalent implementations —
is NOT a blocker. Proceed without asking.

## 3. Project context overlays

`owl step show` returns an `overlays` array alongside `context`. Each
overlay carries `{ source, body, warning }`. Skills MUST merge overlay
bodies into the working context for the step in this order:

1. Built-in `context` (Owl-shipped).
2. Overlays in the order returned (convention paths first, explicit
   config paths after).
3. Task artifacts under `task.artifacts` (current task state).

If an overlay carries `warning: :too_long`, surface a one-line note in
the step log but still include the body.

## 4. Communication style

- One sentence per status update; no narration of internal
  deliberation.
- Reference files as `path:line` so the user can navigate.
- Never claim work is done without verifying via the `owl` CLI
  (`owl status`, `owl artifact validate`, etc.).
