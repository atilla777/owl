---
step_id: "decompose"
applies_to_session_type: "discussion"
intended_audience: "orchestrator"
summary: "Decompose the composite feature into child tasks."
---

# Purpose

Carve the parent's `brief` and `design` into non-overlapping child
slices, author a scoped `brief` for each child, and spawn child tasks
on the `feature` workflow with that brief pre-filled. The
`decomposition.md` artifact records the slicing rationale.

## When to use

After `brief` (and optional `design`) in the `composite_feature`
workflow.

## Inputs

- `brief` artifact.
- `design` artifact when present.

## Outputs

- `decomposition` artifact at `tasks/<PARENT-ID>/decomposition.md`
  listing each child slice, its scope, and how the children compose
  back into the whole.
- One child task per slice, created by piping the slice's brief markdown
  straight to `--brief-body -` (stdin) — do **not** write scratch brief
  files under `tasks/<PARENT-ID>/.briefs/` (that violates the rule against
  touching `tasks/` outside resolved artifact paths):

  ```
  owl task child create PARENT-ID \
    --workflow feature \
    --title "<slice title>" \
    --brief-body - <<'BRIEF'
  ---
  status: approved
  summary: <one-line slice summary>
  ---

  # Problem
  ...
  BRIEF
  ```

  `--brief-body -` writes the child's `brief.md` from stdin and marks the
  child's `brief` step as `done`, so the child workflow starts at `design`
  (its local design) without re-prompting the user. The body passes normal
  brief validation; an invalid body returns a clear error rather than a
  silently-created brief.

## Mode

Interactive. The user confirms the slicing — children must be
non-overlapping and each independently shippable. Questions follow the
Owl skill conventions (numbered options).

### Non-overlapping scope check (do this at decompose time)

Overlapping child file scopes must be caught here, not deferred to
`review_code`. Before spawning children, walk this checklist:

1. List the concrete file/dir scope each child will touch.
2. Confirm no two children claim the same file or directory; if two
   slices need the same file, re-slice (merge them, or carve the shared
   file into its own child the others depend on).
3. Record the per-child scope in `decomposition.md` so the boundaries are
   auditable.

## Notes

Children run the standard `feature` workflow (8 steps). The parent
does **not** wait for children — once `commit_push` runs, the parent
task is workflow-done; children continue independently through the
orchestrator.
