---
step_id: "review_code"
applies_to_session_type: "execution"
intended_audience: "subagent"
summary: "Self-review the code; Owl runs the objective verification gate at completion."
---

# Purpose

Self-review the code changes and record findings, their severity, and the
resolution of each in a `review` artifact. This step also owns the
`verification` artifact and carries the objective verification gate
(`verify: true`).

## When to use

After `implement` in the `feature` workflow.

## Inputs

- Repository diff produced by `implement`.
- `brief` (for acceptance criteria) and `design` (for API contract).

## Outputs

- `review` artifact at `tasks/<TASK-ID>/review.md` with
  `Summary / Findings / Resolution` and front matter status
  `open | resolved`.
- `verification` artifact at `tasks/<TASK-ID>/verification.md`.

## Objective verification gate

This step is flagged `verify: true`. When `settings.verification.command`
is configured, `owl step complete` runs that command itself, derives the
status from its exit code, and **overwrites** `verification.md` with the
objective result — you cannot fake a green status. Completion is refused
unless the objective status is `passed`; a failure keeps the step
`running`. Loop back with `owl step reopen TASK-ID implement --cascade`,
fix the code, and re-run the cycle.

- The whole suite runs synchronously inside `step complete`. Before
  completing a `verify: true` step, refresh your claim
  (`owl task heartbeat` / `--ttl`) so a long run does not outlive the
  lease and let another session steal the task.
- When no command is configured the gate is inactive (fail-open): Owl
  prints a `verification_gate_inactive` warning and you author
  `verification.md` yourself as an honest self-report (status
  `passed | failed | partial`, `Summary / Commands / Outcomes`).

## Mode

Autonomous. Address findings in-line (loop back to `implement` for
fixes) and set `status: resolved` once each finding has a resolution. If
a finding is a true blocker, set `status: open` and surface it to the
user.
