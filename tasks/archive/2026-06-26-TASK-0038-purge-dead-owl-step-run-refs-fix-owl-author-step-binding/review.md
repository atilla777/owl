---
status: resolved
summary: All 9 owl-step-run refs purged from source + re-materialized .claude; owl-author Q6 binds by session_type with escape hatch preserved; version 0.20.1 + CHANGELOG; rspec 0 failures. Approved.
verdict: accepted
ready: true
---

# Review

## Summary

Independent review of TASK-0038, a mechanical documentation/authoring-instruction
hotfix. The change purges every `owl-step-run` reference from the
skills/commands tree (the executor skill was split into `owl-step-discussion` +
`owl-step-execution`) and rewrites `owl-author` Mode A Q6 to bind each authored
step to its `session_type`-matching skill. Scope reviewed: the 5 source files
(`skills/owl-cli`, `skills/owl-init`, `skills/owl-orchestrator`,
`skills/owl-author`, `commands/owl-task-next`), their re-materialized `.claude/`
copies, `lib/owl/version.rb`, `CHANGELOG.md`, plus the `bin/owl upgrade`
side-effects (`.owl/config.yaml`, `Gemfile.lock`). Every acceptance criterion
holds; verdict `accepted`, ready to ship.

## Findings

- None.

Verification performed (all passing):
- `grep -rn owl-step-run skills/ commands/` → exit 1, 0 matches.
- `grep -rn owl-step-run .claude/skills .claude/commands` → exit 1, 0 matches.
- `skills/owl-author/SKILL.md` Q6 asks `session_type (discussion | execution)`,
  binds `owl-step-discussion` / `owl-step-execution` accordingly, AND preserves
  the "unless the user names a different `owl-step-<x>` skill explicitly
  (preserve that verbatim)" escape hatch — the brief's custom-skill edge case.
- Each replacement is contextually correct, not find/replace damage:
  `owl-cli` L110 now accurately describes `owl init` materializing the two
  step skills with each step bound to its `session_type` skill; the orchestrator
  stop-condition example uses `owl-step-execution` (the execution-step skill,
  apt for "could not infer the step's purpose"); `owl-task-next` says "delegates
  to `owl-step-discussion` / `owl-step-execution` by `session_type`".
- `lib/owl/version.rb` = `0.20.1` (patch bump from 0.20.0); `CHANGELOG.md` has a
  matching `## [0.20.1] - 2026-06-26` entry under `### Fixed`.
- All edited prose remains English (constitution 5.16).
- `bundle exec rspec` → 1984 examples, 0 failures, 1 pending (the pre-existing
  SQLite concurrent-write placeholder; unrelated). The guard spec
  `spec/owl/skills/seeded_sources_spec.rb:82` (must not ship legacy
  `owl-step-run` skill/command) passes.
- `git status` is clean of suspicious artifacts: the `.owl/.backup/` directory
  created by `bin/owl upgrade` is gitignored (`.gitignore:20`) and will not be
  committed; it is the only "extra" path and is inert.

## Resolution

No findings to resolve. The `verification` artifact from the implement step was
re-checked rather than trusted: its claims (9 refs purged, Q6 rebound, version
0.20.1, rspec green, backup inert/out-of-scope) were each independently
reproduced and confirmed accurate.

## Remediation

None.

## Residual risks

- `owl-author` is agent-instruction Markdown, not validated code, so the
  `session_type`→`skill` binding is enforced by the LLM following Q6, not by a
  schema check. This matches the plan's explicit out-of-scope note (no Ruby-level
  enforcement) and the seeded `feature`/`hotfix` workflows already bind correctly,
  so the practical risk is low. A future hardening could add a workflow-validate
  rule that every step's `skill` matches its `session_type`, but it is not owed
  by this task.
- The gitignored `.owl/.backup/20260626-*/` snapshot still contains the old
  `owl-step-run` strings; it is an inert backup outside any active load path.
