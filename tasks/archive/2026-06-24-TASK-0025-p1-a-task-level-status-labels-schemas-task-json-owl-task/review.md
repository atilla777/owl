---
status: resolved
summary: "P1-A tracker metadata (status/labels/schemas/task.json/owl task query) reviewed against the approved design; correct, covered, back-compat-safe. One low-severity follow-up: `set-status archived` is allowed and creates a 'ghost archived' task that contradicts the code's own comment and the design intent."
verdict: accepted_with_followups
ready: true
---

# Summary

Reviewed the `implement` diff for TASK-0025 (first-class tracker metadata) against
the approved `brief`/`design`/`plan`. The implementation matches the design:
explicit task-level `status` (enum) + `labels[]` in `task.yaml` and each
`tasks/index.yaml` entry, a formal `schemas/task.json` validated through the
existing `Owl::Validation::Internal::SchemaCheck` walker, and AND-combinable
`owl task query`. All index writes route through the locked `IndexWriter`; no new
bypass. Tests green, coverage gate green, RuboCop net-zero. Schema accepts every
status real task.yaml files hold and validates all 27 live files. One
low-severity semantic wart found (manual `set-status archived`), recorded as a
follow-up — not a blocker.

# Findings

## Verified correct

- **`status` field & enum.** `schemas/task.json` enum is
  `open|in_progress|blocked|on_hold|done|archived|abandoned` (all 7) —
  superset of the design's 6, intentionally including `abandoned` so
  `owl task abandon` output validates. Validated all 27 real `task.yaml` files
  (active + archived) against the schema: every one passes. No live file is
  rejected. Default `open` set at create (`task_writer.rb`). `set-status` is
  enum-gated: `bogus` → `invalid_status` (confirmed live). Status is orthogonal
  to steps (top-level field; step statuses are unconstrained `steps: array`).
- **`labels`.** `add` is idempotent, trimmed and de-duped; `rm` of an absent
  label is a clean `ok:true` no-op (confirmed live: `backend`, repeat,
  `"  backend  "` all collapse to `["backend"]`).
- **`schemas/task.json`.** `additionalProperties: true`, no `required`, all
  fields optional → legacy files validate. `workflow` typed `[object,string]`
  (snapshot vs index projection), `artifacts` `[object,array,null]`. Validated
  via the shared JSON-schema walker (`task_schema.rb` → `SchemaCheck.walk`), not
  a bespoke validator — matches the design.
- **Index.** `build_index_entry` adds `status` (default `open`) and `labels`
  (default `[]`). Audited all index writers: `status_writer`, `label_writer`,
  `abandon_writer`, `deleter`, `archive/mover`, filesystem backend all call
  `IndexWriter.rebuild`; the only direct `IndexRebuilder.rebuild` caller is
  `IndexWriter` itself (under the `index` lock). No lock bypass introduced.
- **`owl task query`.** AND-combined over the index only (no per-file scan).
  `--priority` parsed as `Integer` so it matches the integer index value;
  `--workflow` matches the extracted `workflow_key` string. Confirmed live:
  `--status open --label backend` → only the matching task; `--status archived`
  → the archived one. `owl task list` unchanged.
- **Back-compat.** Legacy `task.yaml` with no `status`/`labels` reads as
  `open`/`[]` in the rebuilt index (covered by
  `spec/owl/tasks/api_tracker_spec.rb` "legacy task.yaml (no status / labels)").
- **AvailabilityScanner (the scrutinized change).** `TERMINAL_STATUSES =
  {archived, abandoned, done}`; `active_entries` now excludes that set instead
  of the old "status empty" check. This is correct: legacy empty status → not
  terminal → still available; `open`/`in_progress`/`on_hold`/`blocked` →
  available; `done`/`archived`/`abandoned` → excluded. Confirmed live: a task set
  to `archived` drops out of `owl task available`, and fresh `open` tasks are
  ranked in. The branch is exercised by the existing `.available` specs
  (open included; abandoned excluded). `on_hold`/`blocked` staying claimable is
  a deliberate deferral (see follow-up), acceptable for P1-A scope.
- **Coverage.** `lib/owl/tasks/api.rb` 91/91 and `lib/owl/cli/api.rb` 242/242 =
  100% line coverage; the 100%-api gate (`spec/spec_helper.rb`, `exit 1` on any
  sub-100% api file) is green with exit 0.
- **Versioning.** `Owl::VERSION` 0.11.0 → 0.12.0 (minor; new feature) +
  CHANGELOG entry. `schemas/**/*.json` is packed by `owl-cli.gemspec`
  (`Gem::Specification.load` confirms `schemas/task.json` ships).

## Low severity

- **L1 — `set-status archived` is allowed and contradicts its own comment.**
  `SETTABLE_STATUSES` in `lib/owl/tasks/internal/task_schema.rb` includes
  `archived`, yet the adjacent comment states "`archived` / `abandoned` are
  excluded here because they are owned by the archive / abandon flows". Live
  test: `owl task set-status TASK-0001 archived` returns `{ok:true,
  status:"archived"}`, sets the field, but does **not** move the task to
  `tasks/archive/` — producing a "ghost archived" task (status `archived`,
  still in the active dir, excluded from `available` but still in `task
  list`/`query`). This diverges from the design ("`archived` ставится системно
  при archive") and from the comment. Not data-corrupting and not in scope of
  any acceptance criterion; recorded as a follow-up rather than a blocker.

# Resolution

All required acceptance criteria are met and verified (live smoke + full suite +
coverage gate + RuboCop). No changes are required to land P1-A. The single
finding (L1) is a low-severity semantic/comment inconsistency, captured under
*Open follow-ups* for a fast-follow; it does not affect correctness of the
shipped tracker fields, query, index integrity, or back-compat.

# Remediation

- **L1 (follow-up, not blocking):** either remove `'archived'` from
  `SETTABLE_STATUSES` (so `owl task set-status ... archived` returns
  `invalid_status`, matching the comment + design and forcing the proper
  `owl archive` move), or, if manual archived-marking is intended, correct the
  comment and document that `set-status archived` only flags status without
  moving the directory. The former is recommended for consistency with
  `abandoned` (already excluded).

# Open follow-ups

- **L1 — `set-status archived` ghost state.** `archived` is user-settable via
  `owl task set-status` (in `SETTABLE_STATUSES`), contradicting the code comment
  and design intent that `archived` is owned by the `owl archive` flow. Result:
  a task can be marked `archived` without being moved to `tasks/archive/`.
  Suggest dropping `archived` from `SETTABLE_STATUSES` (parallel to the already-
  excluded `abandoned`). Low severity.
- **`on_hold`/`blocked` still claimable (deferred by implementer).** Tasks in
  `on_hold`/`blocked` remain in the `available`/auto-claim pool because only
  `{archived,abandoned,done}` are terminal. Whether tracker `on_hold`/`blocked`
  should suppress auto-selection is a workflow-integration decision the
  implementer deliberately deferred. Acceptable for P1-A; worth a dedicated
  task (candidate for the existing TASK-0026/0027 backlog wave).

# Residual risks

- Index ↔ task.yaml drift is mitigated (mutators + create all rebuild the index
  via the locked `IndexWriter`, which full-scans task.yaml as source of truth).
- Schema permissiveness (`additionalProperties:true`, all-optional) means a
  typo'd top-level key in a hand-edited task.yaml would pass validation — an
  accepted design trade-off for upgrade-safety, not a regression.
