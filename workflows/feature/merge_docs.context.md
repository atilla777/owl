---
step_id: "merge_docs"
applies_to_session_type: "execution"
intended_audience: "subagent"
summary: "Merge published docs into the repository and merge any spec_delta into the living spec."
---

# Purpose

Apply the `design` artifact to project documentation under `docs/` per
the workflow's `publishes` rules (flipping the design's front matter
status to `shipped`), AND apply this task's optional `spec_delta`
artifact into its domain's living spec under `specs/<domain>/spec.md`,
gating on requirement→scenario→test traceability.

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

- Files written under `docs/<...>` per `publishes` rules, with
  `.bak-<timestamp>` siblings when an existing file is overwritten.
- `design.md` front matter updated from `approved` to `shipped`.
- When a `spec_delta` is present: `specs/<domain>/spec.md` updated with the
  merged delta (the merged spec is the new contract).

## Mode

Autonomous. Run BOTH commands:

1. `owl publish TASK-ID --json` — honors the workflow `publishes` rules.
   A rule whose source is absent and marked `optional` yields
   `action: skipped_missing_source` (a normal no-op); a missing source on a
   non-optional rule fails with `source_missing`.
2. `owl spec merge TASK-ID --json` — applies the task's `spec_delta` (if
   any) via the deterministic P4 engine, then runs the P5 trace gate
   (`owl spec trace <domain> --strict`). `reason: no_spec_delta` is a
   normal no-op.

When a `spec_delta` IS present, the trace gate MUST pass: a non-zero exit
(`ok: false`) means the merged spec has untraced scenarios or dangling
test refs. Note the delta is still applied (the spec is the new contract);
resolve the trace failure by linking the missing `- TEST:` references (or
fixing dangling ones) before completing the step. Use `--dry-run` to
preview the merge + trace without writing.
