# Purpose

Self-review the code changes and the verification report. Record
findings, their severity, and the resolution of each in a `review`
artifact. Escalate to the user only on real blockers.

## When to use

After `implement` in the `feature` and `feature_slice` workflows.

## Inputs

- Repository diff produced by `implement`.
- `verification` artifact from `implement`.
- `brief` (for acceptance criteria) and `design` (for API contract).

## Outputs

- `review` artifact at `tasks/<TASK-ID>/review.md` with
  `Summary / Findings / Resolution` and front matter status
  `open | resolved`.

## Mode

Autonomous. Delegate the actual review to a subagent with the diff and
the brief/design as context. Address findings in-line (loop back to
`implement` for fixes) and set `status: resolved` once each finding has
a resolution. If a finding is a true blocker, set
`status: open` and surface it to the user.
