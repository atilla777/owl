---
status: resolved
summary: Docs-only sync of agent instructions with the bin/owl surface and unified report-status vocabulary; every acceptance criterion verified, no behavior change, suite green.
verdict: accepted
ready: true
---

# Code review

## Summary

TASK-0039 is documentation/instruction-only: it syncs the agent-facing
instruction layer (`CLAUDE.md`, `skills/owl-cli`, `skills/owl-orchestrator`,
`skills/owl-step-execution`, `skills/_owl_conventions.md`) with the real
`bin/owl` CLI surface, unifies the execution-report status vocabulary onto the
canonical `status` field, and bumps the version (minor) + CHANGELOG. The
`.claude/` copies were re-materialized via `owl upgrade`. I independently
verified every acceptance criterion against the diff, the report JSON schema,
and the test suite. No Ruby/CLI/JSON-contract change was made; the suite is
green. Verdict: accepted.

## Findings

Each acceptance criterion checked independently:

1. **`final_state` → `status` migration complete.** `grep -rn "final_state"
   skills/` → 0 matches; `grep -rn "final_state" .claude/skills` → 0 matches.
   `skills/owl-step-execution/SKILL.md` and `skills/_owl_conventions.md` use
   `status: <x>` everywhere (abort, interrupted, error, stop-conditions).
   `error_message` retained as a supplementary field with an explicit note that
   the schema's `additionalProperties: true` allows it. PASS.

2. **Prose enum matches the JSON schema exactly.** `schemas/step_report.json`
   (`$id .../step_report/v1.json`) field is `status` with enum
   `["returned_normally","do_not_use","error","interrupted","budget_exceeded"]`.
   The reworded prose enum in `owl-step-execution/SKILL.md:54` reproduces it
   verbatim, including `interrupted`/`budget_exceeded`. PASS.

3. **Internal Ruby `final_state` correctly left untouched.** `lib/owl/subagents/
   api.rb` and `lib/owl/subagents/internal/filesystem_report_backend.rb` still
   use `final_state` as the internal result-hash key (a different layer that
   *derives* from the parsed report's `status`). Changing it would have been
   out of scope and wrong; the implementer correctly did not. PASS.

4. **`owl next` in CLAUDE.md Startup Sequence.** `CLAUDE.md:41` lists `bin/owl
   next [TASK-ID] --json` as step 1, describing `action.kind` and noting it is
   read-only. Mutating-commands list extended with `task claim|release|
   heartbeat|adopt`, `step reset`, `plan approve`, `commit-push`, and links to
   the `owl-cli` skill rather than duplicating the surface (stays concise). PASS.

5. **KOS line removed from owl-cli.** `grep -rni "kos" skills/owl-cli/SKILL.md`
   → 0 matches. The stale "current workflow state lives in KOS application
   state" line is replaced with an Owl-authoritative statement. PASS.

6. **owl-cli stop-condition reword genuinely fixes the inconsistency.** Both
   spots reworded: the command-list note (`:104`) — "if an operation is not
   documented here, fall back to `owl --help`; only stop and report if it is
   absent there too" — and the Stop-Conditions clause (`:176`) — "documented
   neither here nor in `owl --help` ... a command reachable via `owl --help` is
   **not** a stop; use it." An agent needing `owl task claim` is now NOT told to
   stop: `claim` is both documented in the refreshed list and reachable via
   `owl --help`. The scenario in the brief is satisfied. PASS.

7. **Orchestrator numbering contiguous AND all cross-refs resolve.** This was
   the highest-risk edit; I traced every reference:
   - Step list is now contiguous 1-9 (was 1,2,3,4,6,7,8,9,10 — the `4→6` gap is
     closed and the tail renumbered down by one). Steps 1-9 all present and in
     order.
   - Cross-refs after renumbering: handoff is now **step 8** (Composite-parent
     handoff) and final report is now **step 9** (Final report).
   - `dispatch_step.handoff_composite` → "Workflow step 8" ✓ (handoff).
   - `dispatch_step.done` → "Workflow step 9" ✓ (final report).
   - Outputs section (`:33`) "completion report at end of run (Workflow step 9)"
     ✓ (final report).
   - Stop-condition #2 "emit the Workflow step 8 handoff" ✓.
   - Stop-condition composite "mandatory handoff of Workflow step 8" ✓.
   - "Workflow step 1" references (`:24`, `:96`, selection ladder) still point to
     step 1 ✓ (unchanged, correct).
   - No leftover "Workflow step 10" anywhere. PASS.

8. **Single completion owner + idempotency documented.** Orchestrator step 6
   now states the executor step skill owns `owl step complete` + final
   `owl artifact validate`, and that an orchestrator re-complete returning
   `step_not_running` is a safe idempotent no-op re-check, not an error. The
   redundant double-resolution (re-deriving the binding via `instructions` +
   `step show`) is trimmed to optional. Matches the brief's "Single completion
   owner" requirement. PASS.

9. **Version + CHANGELOG.** `lib/owl/version.rb` = `0.21.0` (minor bump, correct
   for a feature-level instruction change). `CHANGELOG.md` has a matching
   `## [0.21.0] - 2026-06-26` entry under `### Changed`, accurately describing
   all five edit groups and explicitly noting "no `bin/owl` Ruby, CLI, or
   report-JSON-schema change". `.owl/config.yaml` and `Gemfile.lock` bumped to
   `0.21.0` by `owl upgrade` (expected). PASS.

10. **Prose stayed English; CLAUDE.md stayed concise.** All edited prose is
    English (constitution §5.16). CLAUDE.md added one Startup-Sequence line and
    extended one Mutating-commands line, linking to `owl-cli` rather than
    duplicating the full surface. PASS.

11. **No suspicious/unrelated changes.** `git status` shows only: the 8 doc/skill
    files in scope (source + `.claude/` mirror), `lib/owl/version.rb`,
    `CHANGELOG.md`, the expected `owl upgrade` byproducts (`.owl/config.yaml`,
    `Gemfile.lock`), and TASK-0039 workflow-state files (`task.yaml` step
    progression, `brief.md` draft→approved, new `plan.md`). Nothing unexpected.
    PASS.

## Resolution

All eleven verification points pass. No findings require changes. The diff
exactly matches the approved plan's scope and checklist, the report-status
prose now matches the canonical schema verbatim, the high-risk orchestrator
renumbering is internally consistent with every cross-reference resolving to
its intended target, and the full RSpec suite is green (1984 examples, 0
failures, 1 expected pending). Verdict: **accepted**. No follow-ups.

## Remediation

None required.

## Residual risks

None of substance. This is a docs/instruction change with no executable code
path touched; the only "contract" surfaces (report-status enum, internal
`final_state` key) were verified to be aligned and untouched respectively.
