# Purpose

When the spec leaves architectural choices open, produce a design.md with
Контекст / Решение / Альтернативы / Риски. Optional — skip when the task is simple enough.

## When to use

In `feature` / `composite_feature` workflows when the spec has unresolved architectural
decisions. Skip with `owl step skip TASK-ID design --reason "..."` when the task is
simple enough.

## Inputs

- `spec` artifact.
- Codebase context for any modules the design touches.

## Outputs

- `design` artifact under `tasks/<TASK-ID>/design.md`.

## Notes

This step is optional. If skipping, run `owl step skip TASK-ID design --reason '...'`
instead of `owl step complete`.
