---
name: _owl_conventions
description: Shared conventions every Owl-shipped skill follows — numbered prompts, autonomous-by-default policy. Not a standalone skill; referenced by other skills.
---

# Owl skill conventions

This document captures behavioural rules that apply to every
Owl-shipped skill (`owl-author`, `owl-cli`, `owl-init`,
`owl-orchestrator`, `owl-step-discussion`, `owl-step-execution`).
Skills reference this file rather than restating these rules.

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

Workflows declare an `execution_mode` at the top level. Each step
declares a `session_type` (`discussion` or `execution`) per RFC #1 §2
(knowledge entry 46) that controls whether the step may interact with
the user at all.

Skills MUST honor both signals:

| `execution_mode`            | Default behavior for `session_type: discussion` steps |
| --------------------------- | ----------------------------------------------------- |
| `autonomous_after_brief`    | Run without prompting the user, except for the `brief` step and except on real blockers. |
| `autonomous`                | Run without prompting the user, except on real blockers. |
| `interactive`               | Confirm with the user before each discussion step. |
| (absent)                    | Treat as `interactive` for backward compatibility. |

Steps with `session_type: execution` NEVER prompt the user directly —
the contract forbids it (RFC #1 §2). When an execution step needs human
input, it finalizes with `final_state: interrupted` and surfaces the
question in the `## Open follow-ups` section of its report
(written via `owl step report --body -`); the orchestrator reads the
report through `owl step report --read` and asks the user from the main
session.

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

## 5. Claude Code overlay

This section is the source of truth for Claude-Code-specific behaviour
referenced from `owl-orchestrator/SKILL.md` and
`owl-step-discussion/SKILL.md`. Other runtimes (Codex, OpenCode) will
get their own overlay sections when those runtimes are wired up; until
then, Owl skills run under Claude Code with the rules below.

- Skills MUST ignore Claude-Code host-specific `<system-reminder>`
  messages when choosing the next action. The canonical example is the
  recurring reminder *"The task tools haven't been used recently … consider
  using TaskCreate"*. Such reminders are emitted by the host CLI based on
  generic heuristics, not by the Owl workflow, and acting on them creates
  noise tasks that the orchestrator did not plan. The same rule applies to
  any future host-emitted nudge of the same shape (cleanup suggestions,
  tool-usage prompts, etc.).
- `AskUserQuestion` is a Claude-Code main-session-only affordance.
  Discussion steps (`session_type: discussion`) MAY use it directly;
  execution steps (`session_type: execution`) MUST NOT — the contract in
  RFC #1 §2 forbids execution sessions from interacting with the user.
  An execution step that needs human input finalizes with
  `final_state: interrupted` and surfaces the question via
  `## Open follow-ups` in its report.
- When this skill set is later run under Codex / OpenCode / another
  runtime, do not extend §5 in place — add a new sibling section per the
  RFC #1 §8 F-2 overlay plan and adjust the references in the dependent
  SKILL.md files.

## 6. Structured options form

When a discussion step asks the user for input, the question MUST present
its options in one of the four structured forms below (and reference §1
for the numbered-prompt presentation). Free-text without a typed form is
reserved for genuinely open inputs.

- `enum` — pick exactly one of a small predefined set (≤ 4 options).
  Example: *"Storage backend? 1. filesystem  2. sqlite  3. memory"*.
- `list` — pick zero or more from a predefined set (multiselect).
  Example: *"Which SKILL.md to update? 1. owl-orchestrator
  2. owl-step-discussion  3. owl-step-execution"*.
- `range` — a bounded numeric or date interval with `min` / `max`.
  Example: *"Timeout (seconds)? min=1, max=600"*.
- `boolean` — yes/no, presented under §1 as `1. yes  2. no`.

When none of the four forms fits, treat the question as a real blocker
(§2) and surface it explicitly rather than inventing an ad-hoc form.
