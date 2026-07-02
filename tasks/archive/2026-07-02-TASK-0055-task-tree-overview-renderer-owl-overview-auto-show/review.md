---
status: resolved
summary: owl overview triplet + StepStatus extraction meet the brief/design/plan; layering, marker vocabulary, behaviour-preserving refactor, seed mirroring and version bump all verified — no defects, verdict accepted.
verdict: accepted
ready: true
---

## Summary

Self-review of the `implement` diff for TASK-0055 (task-tree overview renderer).
The change adds the `owl overview` command as a `command + data + renderer`
triplet under `lib/owl/cli/internal/commands/`, extracts a shared
`Owl::StepStatus` module and switches four call sites to it, adds the
`settings.ui.auto_render_tree` config flag with orchestrator wiring, seeds a
`/owl-overview` command wrapper, bumps `Owl::VERSION` to 1.8.0 and adds a
`CHANGELOG.md` entry, plus a comprehensive `overview_command_spec.rb`.

Assessed against the brief's acceptance criteria and the design's API contract.
The implementation matches the design decision-by-decision. No substantive
defects found; the review is clean (verdict `accepted`).

## Findings

Every acceptance criterion and design decision was checked; all pass.

1. **Correctness of `owl overview` (all scenarios)** — verified by smoke tests
   on the live repo and by the new spec:
   - Forest with hierarchy: parent → child rendered with `├─`/`└─` connectors,
     status markers, and `workflow: KEY` (rich mode).
   - Subtree by `TASK-ID`: renders only that task's descendants (uses
     `Tasks::Api.tree(root_id:)`).
   - `--all`: archived/abandoned included; hidden by default
     (`HIDDEN_STATUSES = %w[archived abandoned]`; note `done` non-archived
     tasks correctly remain visible per the brief, which prunes only
     archived/abandoned).
   - `--compact`: drops workflow key and progress bar, keeps marker/id/title
     and current/blocking annotations (matches the compact scenario).
   - `--json`: exact `{ok, tree, current_task_id, warnings}` shape with the
     full node field set (`id,title,workflow_key,kind,status,parent_id,
     progress{done,total,pct},current,blocked_by,unmet_deps,children`).
   - Current highlight: `◀ текущая` added as annotation *in addition to* the
     status marker; broken current pointer renders without highlight, no crash.
   - Inline deps: `⛔ ждёт TASK-XXXX` for unmet `blocked_by`; a dep that is
     `done`/`archived`/absent counts complete and clears the annotation
     (mirrors `ready_scanner.deps_complete?`, DAG-arrow-free per brief).
   - Empty forest: prints `нет запланированных задач`, not blank/traceback.
   - Unknown `TASK-ID`: structured `task_not_found` error on stderr, exit 1.
   - Cycle/depth: `warnings` from `Tasks::Api.tree` propagated to both ASCII
     (`⚠️ tree_cycle @ …`) and JSON; no infinite loop.

2. **Layering (docs/agents/27)** — `overview_data.rb` reads exclusively through
   `Owl::Tasks::Api` (`.tree`, `.list`, `.current_task_id`) and
   `Owl::Status::Api.show`. No direct FS reads of `.owl/`/`tasks/`/`docs/`.
   No new `lib/owl/**/api.rb` lines were added, so the 100%-api-coverage rule
   is not triggered; the new CLI logic is covered directly by the command spec.

3. **`Owl::StepStatus` extraction is behaviour-preserving** — verified value
   equality at all four call sites: `status/internal/constants.rb`
   (DONE `%w[done skipped]`, BLOCKER `%w[blocked failed]`),
   `workflow_diagram_data.rb` (same), `workflow_diagram_renderer.rb` (markers,
   bar glyphs, BLOCKED `%w[blocked failed]`; the `done`/`skipped`-split sets
   correctly stay local), and `next_action_resolver.rb`
   (`(%w[running] + BLOCKING_STATUSES) == %w[running blocked failed]`, order and
   freeze preserved). Full suite stayed green (see verification), proving no
   behavioural drift.

4. **Marker/bar vocabulary reused** — the renderer draws all markers
   (`[✓][▶][ ][~][!]`) and progress glyphs (`━`/`·`, width 10) from
   `Owl::StepStatus`, consistent with `owl workflow show`. No divergent set.

5. **Seed edits mirrored, orchestrator gated, version/CHANGELOG** —
   `commands/owl-overview.md` and `.claude/commands/owl-overview.md` are
   byte-identical (owl-workflow-show is likewise command-only; auto-enumerated
   by `SeededSources` scanning `commands/`; both `init_skills_spec` and
   `seeded_sources_spec` updated to expect it). `settings.ui.auto_render_tree`
   documented in both `skills/` and `.claude/skills/` copies of owl-init and
   owl-orchestrator; orchestrator auto-render explicitly gated on the flag and
   scoped to start-of-drive + `handoff_composite` (not every loop). `.owl/config`
   version and `Owl::VERSION` bumped to 1.8.0; CHANGELOG entry present. Config
   `settings.ui.auto_render_tree` registered.

6. **Ruby conventions (docs/agents/28/29/30)** — RuboCop clean on all nine
   touched files; module-function service-object style consistent with the
   `workflow_show` triplet; spec covers all brief scenarios (11 examples,
   0 failures).

## Resolution

No findings required a fix — the diff is correct and complete against the
acceptance criteria. Nothing was changed in the working tree during review.
The step's objective gate is inactive (`settings.verification.command` is
`null`); the full RSpec suite was run manually as the honest self-report
(see `verification.md`): 2144 examples, 0 failures, 1 pre-existing pending
(unrelated SQLite storage-contract placeholder).

## Remediation

None required.

## Residual risks

- **Perf on `--all` with a large archive** — one `Status::Api.show` per node,
  accepted by the design; only material for very large archives and behind an
  opt-in flag.
- **Objective verify gate inactive** — because `settings.verification.command`
  is unset, `owl step complete` will fail-open with a `verification_gate_inactive`
  warning rather than re-run the suite; the green suite here is a manual
  self-report. This is a pre-existing repo-wide condition, not introduced by
  this task.
