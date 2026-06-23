# Changelog

All notable changes to `owl-cli` are documented here. The format is loosely
based on [Keep a Changelog](https://keepachangelog.com/); this project uses
semantic versioning.

## [0.3.0] - 2026-06-23

### Added
- **Objective verification gate (`verify: true` step-marker + `owl verify`).**
  A step can now opt into an objective verification gate with a boolean
  `verify: true` marker (mirroring the `publishes: true` precedent). At
  `owl step complete`, Owl itself runs the project's
  `settings.verification.command` as a subprocess, derives the status from its
  exit code, and **authors** the `verification` artifact — the status can no
  longer be faked by an agent self-report. Completion is refused (structured
  `verification_failed`, non-zero exit, step stays `running`) unless the
  objective status is `passed`; the result is fresh by construction because the
  run happens at completion time. Fix a failure with
  `owl step reopen TASK-ID implement --cascade`.
- New `Owl::Verification` domain (`Api.run` / `Api.gate` /
  `Api.configured_command`, with injectable `Internal::CommandRunner`,
  `Internal::Engine`, `Internal::Gate`, `Internal::ReportWriter`).
- **`owl verify TASK-ID [--json]`** — run the verification command for a task
  without completing a step (a convenience pre-check); reports
  `{ok, status, exit_code, command, gate_active}`. `gate_active: false` with a
  warning when no command is configured.
- `settings.verification.command` (string|null) and
  `settings.verification.timeout_seconds` (positive integer, default 1800) are
  now recognized and validated in `.owl/config.yaml`
  (`invalid_settings_verification_shape` /
  `invalid_settings_verification_command` /
  `invalid_settings_verification_timeout`). A commented example ships in the
  default config template. New workflow step field `verify` (boolean) in
  `schemas/workflow.json`.

### Changed
- **Verification ownership moved from `implement` to `review_code`.** In the
  seeded `feature` workflow `creates: [verification]` now lives on `review_code`
  (alongside `creates: [review]`), which carries `verify: true`; `implement`
  becomes a build-only step that creates no artifact. Step context files updated
  accordingly. Only new tasks pick up the new graph (in-flight `task.yaml` files
  are untouched).

### Compatibility
- **Opt-in and fail-open.** With no `settings.verification.command` configured,
  the gate is inactive: `owl step complete` proceeds and prints a
  `verification_gate_inactive` warning. A `partial` status does not block
  (warning only). Existing consumers that do not configure a command keep their
  current behaviour across `owl upgrade`.

## [0.2.0] - 2026-06-23

### Added
- **`owl next [TASK-ID] --json` — read-only next-action advisor.** A new
  top-level command that encapsulates the orchestrator's whole "what do I do
  next?" decision in code instead of skill prose. It runs the canonical
  selection ladder (explicit `TASK-ID` › current pointer › auto-select the top
  `owl task available` candidate) and classifies the outcome into a single
  discriminated `action.kind ∈ {dispatch_step, handoff_composite, stop_blocked,
  done, no_available_task}`. All outcomes exit 0 (a terminal outcome is a valid
  result, not an error); the raw `no_current_task` error no longer leaks — it
  maps to `no_available_task`. `task_resolution` reports `source ∈ {explicit,
  current_pointer, auto_select, none}` with a `reason` and a `needs_adopt` flag
  (set when the chosen task has an expired lease over a stuck `running` step).
  The command is idempotent and never mutates state (no claim, no step start) —
  claim/adopt remain explicit orchestrator follow-ups.
- New `Owl::Orchestration` domain (`Api.next_action`, read-only
  `Internal::NextActionResolver` + shared `Internal::TaskResolver`) composing
  the existing Tasks/Workflows/Steps APIs.

### Changed
- **Skill prose deduplicated.** `owl-orchestrator` Workflow §1 (selection
  ladder) and §4 (pick next step) now delegate to `owl next --json` and dispatch
  by `action.kind`, keeping the mutation sections (claim/adopt/heartbeat/steal/
  multi-session) as a thin reference. `owl-cli` documents `owl next` and its
  response shape. The current→pointer resolution ladder duplicated in
  `Instructions`/`Status` now reuses a shared `Tasks::Api.current_task_id`
  primitive (behavior-neutral).

## [0.1.1] - 2026-06-23

### Added
- **Communication-language clause for orchestrator/step skills.** Brought
  `owl-orchestrator`, `owl-step-discussion`, and `owl-step-execution` into
  compliance with Constitution 5.16/5.17: every user-facing string is now
  required to be emitted in `settings.language.communication`, documented once
  in `_owl_conventions.md` §7 and referenced from each skill.
- **Session-level (orchestrator) overlay.** `owl overlay show <key>` already
  resolved any key; `_owl_conventions.md` §8 reserves the `orchestrator` key as
  a session-level overlay applied to the orchestrator's end-of-run report. The
  orchestrator now reads `owl overlay show orchestrator` before its final
  summary and folds the body in.
- **Required final-report structure** in `owl-orchestrator`: what changed for
  the user / technically / verification / docs / commit / next, with an explicit
  never-omit user-facing-delta rule (technical-only tasks must say so).
- `owl init` scaffolds `.owl/overlays/orchestrator.md` (commented stub,
  `preserve_if_exists`) as a discoverable, backward-compatible extension point.

### Fixed
- `owl task child create --brief` now records `content_sha` on the seeded brief
  step, so drift detection works for pre-authored child briefs (parity with
  normal `owl step complete`).
- Synced the `workflows/{feature,composite_feature}/commit_push.context.md`
  source seeds with their materialized `.owl/` copies, which had drifted since
  the Phase-4 `owl git lock/unlock` push-serialization work. Fresh `owl init`
  now gives new projects the push-lock sequence; `owl upgrade --dry-run` is
  clean.

### Notes
- Backward compatible: projects without an `orchestrator` overlay fall back to
  the default report structure; existing step-level overlays are unchanged.
- Regression specs cover the language clause across the three skills, the
  orchestrator-overlay composition, non-step overlay-key resolution, the seeded
  brief `content_sha`, and the scaffolded orchestrator overlay.

## [0.1.0]

- Initial Owl CLI: self-hosted, spec-driven workflow engine (tasks, workflows,
  artifacts, steps, overlays, claims/locks, publish/archive).
