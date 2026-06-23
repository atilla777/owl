# Changelog

All notable changes to `owl-cli` are documented here. The format is loosely
based on [Keep a Changelog](https://keepachangelog.com/); this project uses
semantic versioning.

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
