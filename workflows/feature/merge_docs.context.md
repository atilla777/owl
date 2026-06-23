---
step_id: "merge_docs"
applies_to_session_type: "execution"
intended_audience: "subagent"
summary: "Publish task artifacts into docs/ per the workflow's publishes rules, flip the design to shipped, refresh the docs/README.md index, and apply any spec_delta into the living spec."
---

# Purpose

Publish this task's artifacts into `docs/` per the workflow's `publishes`
rules, flip the published `design`'s front-matter `status` from `approved`
to `shipped` (source + copy stay consistent), (re)generate the
`docs/README.md` index of published task docs, AND apply this task's
optional `spec_delta` artifact into its domain's living spec under
`specs/<domain>/spec.md`, gating on requirement→scenario→test
traceability.

This step does not build a searchable aggregate; `docs/` holds per-task
artifact copies plus a generated index. The living spec
(`specs/<domain>/spec.md`) and cross-task memory carry durable knowledge.

## When to use

After `review_code` in the `feature` workflow. Both halves of this step
are no-ops when their input is absent, so a task that touches no docs and
no spec passes through cleanly:

- If `design` was skipped, the workflow's `publishes` rule for `design.md`
  is marked `optional`, so `owl publish` reports
  `action: skipped_missing_source` for it and writes nothing — the step
  still succeeds. (This is NOT the same as `no_publishable_step`, which
  means the workflow has no publishing step at all — a misconfiguration.)
- If the task declares no `spec_delta`, `owl spec merge` returns
  `{ok: true, applied: false, reason: "no_spec_delta"}` and writes nothing.

## Inputs

- Approved `design` artifact (optional) + workflow `publishes` rules.
- Optional `spec_delta` artifact (`tasks/<TASK-ID>/spec_delta.md`): front
  matter `domain` + the `## ADDED|MODIFIED|REMOVED Requirements` sections.

## Outputs

- Files copied under `docs/<...>` per `publishes` rules, with
  `.bak-<timestamp>` siblings when an existing artifact copy is overwritten.
- `design.md` front-matter flipped from `approved` to `shipped` in the
  canonical source (`tasks/<ID>/design.md`) BEFORE the copy, so the
  published `docs/<ID>/design.md` carries `shipped` too.
- A regenerated `docs/README.md` index listing every published
  `docs/TASK-*/` doc with links (deterministic, no timestamps — the
  generated index is not backed up because it is reproducible from `docs/`).
- When a `spec_delta` is present: `specs/<domain>/spec.md` updated with the
  merged delta (the merged spec is the new contract).

## Mode

Autonomous. Run BOTH commands:

1. `owl publish TASK-ID --json` — honors the workflow `publishes` rules.
   A rule whose source is absent and marked `optional` yields
   `action: skipped_missing_source` (a normal no-op); a missing source on a
   non-optional rule fails with `source_missing`. The result also carries
   `design_status` (`flipped_to_shipped` | `already_shipped` |
   `not_applicable`) and `index` (`{updated, path: "docs/README.md"}`).
2. `owl spec merge TASK-ID --json` — applies the task's `spec_delta` (if
   any) via the deterministic P4 engine, then runs the P5 trace gate
   (`owl spec trace <domain> --strict`). `reason: no_spec_delta` is a
   normal no-op.

When a `spec_delta` IS present, the trace gate MUST pass: a non-zero exit
(`ok: false`) means the merged spec has untraced scenarios or dangling
test refs. Note the delta is still applied (the spec is the new contract);
resolve the trace failure by linking the missing `- TEST:` references (or
fixing dangling ones) before completing the step. Use `--dry-run` to
preview the publish + merge + trace without writing (no flip, no index).
