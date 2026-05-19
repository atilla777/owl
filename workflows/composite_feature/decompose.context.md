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
- One child task per slice, created with:

  ```
  owl task child create PARENT-ID \
    --workflow feature \
    --title "<slice title>" \
    --brief tasks/<PARENT-ID>/.briefs/<slice-slug>.md
  ```

  The `--brief` flag pre-writes the child's `brief.md` and marks the
  child's `brief` step as `done`, so the child workflow starts at
  `design` (its local design) without re-prompting the user.

## Mode

Interactive. The user confirms the slicing — children should be
non-overlapping and each independently shippable. Questions follow the
Owl skill conventions (numbered options).

## Notes

Children run the standard `feature` workflow (8 steps). The parent
does **not** wait for children — once `commit_push` runs, the parent
task is workflow-done; children continue independently through the
orchestrator.
