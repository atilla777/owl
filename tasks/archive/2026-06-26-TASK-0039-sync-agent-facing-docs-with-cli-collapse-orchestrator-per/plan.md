---
status: approved
summary: Sync CLAUDE.md + owl-cli with the real CLI surface, fix the report-status vocabulary to one canonical `status` field, and document single-completion-owner / idempotency in the orchestrator.
---

# Plan

## Goal

Close the drift between the agent-instruction layer (CLAUDE.md, `owl-cli`,
`owl-orchestrator`, `owl-step-execution`, `_owl_conventions.md`) and the real
`bin/owl` surface, so an agent bootstrapping from the docs gets the orchestrator's
current mental model, never stalls on a reachable command, and advances a step in
fewer CLI calls with one clear completion owner. Bump `Owl::VERSION` (minor) +
CHANGELOG (skills/** + CLAUDE.md are consumer-materialized).

## Scope

- `CLAUDE.md` — Startup Sequence + Mutating-commands list.
- `skills/owl-cli/SKILL.md` — KOS line (L37), stop-condition wording (L92, L164), command-list freshness.
- `skills/owl-orchestrator/SKILL.md` — single completion owner + idempotent re-complete; fix numbering (skipped "5").
- `skills/owl-step-execution/SKILL.md` — `final_state` → canonical `status` (L54 enum, L75, L78, L111, L119).
- `skills/_owl_conventions.md` — `final_state` → `status` (L54, L117).
- `lib/owl/version.rb` + `CHANGELOG.md`.

## Constraints

- The report-status JSON schema (`schemas/.../step_report/v1.json`, field `status`,
  enum `returned_normally|do_not_use|error|interrupted|budget_exceeded`) is the
  canonical contract — align prose TO it; do NOT change the schema.
- SKILL.md / CLAUDE.md prose stays English (constitution 5.16).
- Guidance must stay generic for custom (non-seeded) workflows that bind their own skills.
- Keep CLAUDE.md concise — link to skills, don't duplicate the full surface.
- No `bin/owl` Ruby/CLI/JSON behavior change — docs/instructions only.

## Files to inspect

- `schemas/**/step_report*.json` (or wherever the v1 report schema lives) — confirm the canonical field is `status` and its enum, before rewording prose.
- `skills/owl-step-execution/SKILL.md` full body — every `final_state`/`error_message` mention.
- `skills/owl-orchestrator/SKILL.md` step list — confirm the numbering gap and the existing completion/validate wording before editing.

## Checklist

- [ ] `CLAUDE.md` Startup Sequence: add `owl next [TASK-ID] --json` as the canonical "what's next?" call (the orchestrator entrypoint), alongside the existing read calls.
- [ ] `CLAUDE.md` Mutating-commands list: extend with the concurrency + delivery surface currently omitted — `task claim/release/heartbeat/adopt`, `commit-push`, `plan approve`, `step reset` (keep it a concise list, link to `owl-cli` for detail).
- [ ] `skills/owl-cli/SKILL.md` L37: remove the stale KOS line (no current KOS state; this repo is Owl-managed).
- [ ] `skills/owl-cli/SKILL.md` L92 + L164: reword the stop-condition so a command reachable via `owl --help` is NOT a stop — "if an operation is not documented here, fall back to `owl --help`; only stop if it is absent there too." (resolves the internal inconsistency where L92 was stricter than L164).
- [ ] `skills/owl-cli/SKILL.md`: refresh the documented command list so the concurrency/claim/commit-push/plan surface an agent actually needs for the loop is represented (or explicitly point to `owl --help` for the long tail).
- [ ] `skills/owl-orchestrator/SKILL.md`: state explicitly that the **executor step skill owns** `owl step complete` + the final `owl artifact validate`, and that a `step_not_running` / idempotent re-complete by the orchestrator is a safe no-op re-check, not an error. Trim the redundant double-resolution guidance (`next` already returns `session_type/skill`; no need to re-derive via `instructions`+`step show`).
- [ ] `skills/owl-orchestrator/SKILL.md`: fix the Workflow step numbering so it has no gap (currently jumps 4 → 6).
- [ ] `skills/owl-step-execution/SKILL.md` L54, L75, L78, L111, L119: replace `final_state: <x>` with the canonical `status: <x>` field, using the schema enum values (`interrupted`, `error`, `returned_normally`, …). Keep `error_message` as the supplementary field if the schema allows it (additionalProperties: true).
- [ ] `skills/_owl_conventions.md` L54, L117: same `final_state` → `status` alignment.
- [ ] `lib/owl/version.rb`: bump minor.
- [ ] `CHANGELOG.md`: new version heading + entry (TASK-0039).
- [ ] Re-materialize `.claude/` copies (`bin/owl upgrade`) so the consumer-facing copies of the edited skills/commands match.

## Tests and verification

- `grep -rn "final_state" skills/ ` → 0 matches (all moved to `status`); confirm `.claude/` copy too.
- `grep -n "owl next" CLAUDE.md` → present in Startup Sequence.
- `grep -rn -i "kos" skills/owl-cli/SKILL.md` → 0 matches.
- `skills/owl-orchestrator/SKILL.md` Workflow section has contiguous numbering (no missing "5").
- `bundle exec rspec` stays green (report the real failure count; this repo can exit red with 0 failures). If any spec asserts on the report `final_state` field name or the version string, update it.
- Manually confirm the report-status enum used in prose matches the JSON schema enum exactly.

## Smoke test

`grep -rn final_state skills/ .claude/skills` returns nothing; `grep -n "owl next" CLAUDE.md` returns a Startup-Sequence hit; `grep -ni kos skills/owl-cli/SKILL.md` returns nothing.

## Out of scope

- Changing the report-status JSON schema or any `bin/owl` behavior.
- A wholesale rewrite of `owl-orchestrator` — only the completion-owner/idempotency clarifications, numbering fix, and trimming the explicitly-redundant double-resolution.
- Rewriting CLAUDE.md beyond the two enumerated sections.
