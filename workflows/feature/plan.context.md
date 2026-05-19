# Purpose

Break the brief's acceptance criteria and the design's API into an
ordered checklist of concrete code changes so `implement` can execute
without re-deciding.

## When to use

After `brief` (and optional `design`) in the `feature` and
`feature_slice` workflows.

## Inputs

- `brief` artifact.
- `design` artifact when the previous step produced one.

## Outputs

- `plan` artifact at `tasks/<TASK-ID>/plan.md` — `Goal` paragraph plus a
  `Checklist` of `- [ ]` items, each naming a file path and the change.

## Mode

Autonomous. Do not ask the user to choose between implementation
options — those choices belong in `design`. Ask only on a real blocker.
