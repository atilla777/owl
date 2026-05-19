# Purpose

Self-review the slice's code changes and verification report. Record
findings and resolutions in a `review` artifact. Escalate to the user
only on real blockers.

## When to use

After `implement` in the `feature_slice` workflow. Last step of the
slice — the parent composite handles `merge_docs`, `archive`, and
`commit_push` for the whole family.

## Inputs

- Repository diff produced by `implement`.
- `verification` artifact from `implement`.
- Parent's `brief` (for acceptance criteria) and `design` (for API
  contract).

## Outputs

- `review` artifact at `tasks/<TASK-ID>/review.md` with
  `Summary / Findings / Resolution` and front matter status
  `open | resolved`.

## Mode

Autonomous. Delegate the actual review to a subagent with the diff and
the parent's brief/design as context. Address findings in-line (loop
back to `implement`) and set `status: resolved` once each finding has
a resolution.
