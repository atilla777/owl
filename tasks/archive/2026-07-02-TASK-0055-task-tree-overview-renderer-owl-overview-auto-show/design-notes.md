# TASK-0055 — Task-tree overview renderer (seed decisions)

Captured from the design discussion on 2026-07-02. This is the input to the
`brief` step, not the brief itself.

## Problem

Give the Owl user a concise, clear picture of what is planned: the task tree
(parent/child hierarchy), each task's status, cross-task dependencies, and which
task is current. Present it as pseudographic ASCII, consistent with the existing
`owl workflow show` marker vocabulary.

## What already exists (reuse, don't reinvent)

- Data is fully available as JSON; only a renderer is missing.
  - Hierarchy: `owl task tree` → `tasks/internal/tree_builder.rb` (nested forest + status).
  - Deps: `blocked_by[]` in `tasks/index.yaml`; readiness in `ready_scanner.rb`.
  - Per-task progress + blockers + children: `owl status` → `status/internal/builder.rb`.
  - Composite roll-up: `owl task aggregate-status`.
  - Current / next: `owl next` (`action.kind`) + `owl task current`.
- Only ASCII renderer today: `cli/internal/commands/workflow_diagram_renderer.rb`
  — flat step list for ONE task. Marker vocab to reuse: `[✓]`done `[▶]`current
  `[ ]`pending `[~]`skipped `[!]`blocked; progress bar `━`/`·` width 10.
- Status-constant sets are duplicated across ~4 files (status/constants.rb,
  workflow_diagram_data.rb, workflow_diagram_renderer.rb, next_action_resolver.rb).

## Decisions (user, 2026-07-02)

1. **Scope — BOTH.** Default `owl overview` = whole forest of non-terminal tasks
   with hierarchy; `owl overview TASK-ID` = that subtree. Hide archived/abandoned
   by default; `--all` shows them.
2. **When (auto-show) — decision points, config-gated.** New flag
   `settings.ui.auto_render_tree` (mirror existing `settings.ui.auto_render_diagram`).
   Auto-render once at the start of an `/owl-orchestrator` drive and on
   `action.kind == handoff_composite`. NOT per-step (per-step is already covered by
   `owl workflow show`). Explicit request always renders.
3. **Detail — RICH.** Per node: marker + ID + title + workflow + progress bar +
   N/M steps + dependency annotation. `--compact` drops to minimal (marker + ID +
   title + current/block marker).

### Secondary decisions (defaults)

- **Dependencies** shown as inline annotation `⛔ ждёт TASK-XXXX` (not DAG arrows;
  an arbitrary DAG does not fit a tree layout and turns to noise in a terminal).
- **Consolidate** the duplicated status-constant sets into one shared module as
  part of this work, so the new view stays in sync with the rest.

## Rough shape

```
Owl · обзор задач                          текущая ▸ TASK-0052

[▶] TASK-0050  owl doctor/reconcile      feature  ━━━━······ 3/8
    ├─ [✓] TASK-0051  version drift check feature  done
    ├─ [▶] TASK-0052  skills hardening    feature  выполняется  ◀ текущая
    └─ [!] TASK-0053  final rollup        feature  ⛔ ждёт TASK-0052
[ ] TASK-0049  gate-ordering wart         feature  ⛔ ждёт TASK-0048
[ ] TASK-0048  build health              hotfix    ·········· 0/4
```

## Implementation notes (for design/plan steps)

- New renderer `cli/internal/commands/task_tree_renderer.rb` next to the workflow
  one; reuse its marker vocab and progress bar.
- Feed it from `tree_builder` data enriched with per-task status (progress) and the
  current-task marker; annotate deps from `blocked_by[]`.
- New command `owl overview [TASK-ID] [--all] [--compact] [--json]` (keep `--json`
  passthrough — JSON is the house default).
- New seed skill `/owl-overview` (thin CLI wrapper), materialised by `owl init`.
- Wire auto-render into `owl-orchestrator` SKILL.md behind `settings.ui.auto_render_tree`.
- Versioning: minor `Owl::VERSION` bump + CHANGELOG entry (new command + seed skill).
  Mirror workflow/skill seed edits into both `workflows/` and `.owl/workflows/`,
  and refresh `.claude/` via `owl upgrade`.
```
