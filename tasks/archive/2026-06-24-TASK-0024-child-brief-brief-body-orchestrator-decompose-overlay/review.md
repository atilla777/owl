---
status: resolved
summary: "FF5 (--brief-body - stdin child brief, validated) + FF6 docs reviewed; code correct, back-compat preserved, decompose copies identical, api.rb 100% gate green, version bump correct. Verdict accepted."
verdict: accepted
ready: true
---

# Review

## Summary

Self-review of the TASK-0024 diff (FF5 `--brief-body -` for `owl task child
create` + FF6 skill/overlay/decompose doc edits). The implementation matches the
approved brief and plan, all acceptance criteria are met, the objective checks are
green (1814 examples / 0 failures, `lib/owl/tasks/api.rb` at 100% line coverage,
RuboCop net-zero on the 7 changed files), and no defect was found. Verdict:
**accepted**.

Files reviewed:
- `lib/owl/cli/internal/commands/task_child_create.rb`
- `lib/owl/tasks/api.rb`
- `lib/owl/tasks/backends/filesystem.rb`
- `lib/owl/tasks/internal/child_creator.rb`
- `lib/owl/version.rb`, `CHANGELOG.md`, `Gemfile.lock`
- `workflows/composite_feature/decompose.context.md` + `.owl/` copy
- `skills/_owl_conventions.md`, `skills/owl-orchestrator/SKILL.md`,
  `skills/owl-step-execution/SKILL.md`
- `spec/owl/cli/task_child_create_spec.rb`, `spec/owl/tasks/child_creator_spec.rb`

## Findings

### FF5 — `--brief-body -` (code)

1. **Body IS validated before `brief` flips to `done` (no silent done).** PASS.
   `child_creator.rb#seed_brief` writes the body, then (only when
   `validate_brief: true`) calls `brief_validation_error`, which runs
   `Owl::Validation::Api.artifact` and returns a `:brief_invalid` `Result::Err`
   when any `level: 'error'` violation exists — *before* the `status: done`
   write. The `Result::Err` propagates through `child_create` → CLI, which emits
   the failure envelope, and the brief step stays `pending`. The validation
   result shape (`:valid`, `:violations` with `:level`/`:description`) matches
   `artifact_runner.rb`, and `brief_validation_error` defensively reads both
   symbol and string keys. Verified by tests: invalid stdin body → `brief_invalid`
   + brief `pending` (both CLI-level and `child_creator`-level specs).

2. **`--brief PATH` and no-brief paths unchanged (back-compat).** PASS. The CLI
   passes `validate_brief: !options[:brief_body].nil?`, so a `--brief PATH`
   invocation (and the no-brief invocation) keep `validate_brief: false` and skip
   the new validation branch entirely — byte-for-byte prior behaviour. A dedicated
   `child_creator` spec asserts the default `validate_brief: false` accepts an
   invalid body and still marks `brief: done` (proving `--brief` parity).

3. **Mutual exclusion of `--brief` + `--brief-body`.** PASS. Enforced in the CLI
   `run` before any stdin read or filesystem mutation, returning
   `code: :invalid_arguments` with a "mutually exclusive" message. Stdin is not
   consumed on the error path. Covered by a CLI spec.

4. **New `tasks/api.rb` branch covered (gate).** PASS. `child_create` gained the
   `validate_brief: false` kwarg threaded to the backend. Coverage resultset shows
   `lib/owl/tasks/api.rb` with **zero** missed lines; both `validate_brief: true`
   and the `false` default are exercised. No "Public API files below 100%" gate
   block printed.

5. **stdin convention.** PASS. `-` reads `$stdin.read`, otherwise the literal is
   used inline — consistent with `workflow context set --body -`. Usage banner and
   `--help` updated; `success_payload` / `resolve_brief_body` / `read_inline_brief_body`
   extractions keep AbcSize within the cop and read cleanly.

### FF6 — docs

6. **Decompose root and `.owl/` copy identical.** PASS. `diff
   workflows/composite_feature/decompose.context.md
   .owl/workflows/composite_feature/decompose.context.md` → IDENTICAL (no drift).
   The `.briefs/` scratch flow is replaced by a `--brief-body -` heredoc, with an
   explicit "do **not** write scratch brief files under `tasks/<PARENT>/.briefs/`"
   instruction and a new "Non-overlapping scope check (do this at decompose time)"
   checklist.

7. **Parallel-command discipline.** PASS. `_owl_conventions.md` §10 forbids
   dispatching a mutator→reader pair (esp. `step start` → `step show`) in the same
   parallel batch; `owl-step-execution/SKILL.md` step 2 references §10 and spells
   out the sequential requirement.

8. **`changes_required` cleanup doc.** PASS. `owl-orchestrator/SKILL.md` step 7
   documents that a `changes_required` verdict leaves `review_code` `running` and
   requires a manual `owl step reset TASK-ID review_code` (docs only, no code
   auto-reset).

9. **Version + CHANGELOG.** PASS. `Owl::VERSION` 0.10.0 → 0.11.0 (minor — new CLI
   flag + changed consumer-materialized seed docs), `Gemfile.lock` synced to
   0.11.0, and a `## [0.11.0] - 2026-06-24` CHANGELOG entry covers Added
   (`--brief-body`) and Changed (decompose flow + skill docs).

## Resolution

All findings resolved/PASS. No code changes required during review. The single
worth-noting nuance is a wording nit, not a defect (see Remediation). Verdict
**accepted**; downstream `merge_docs` → `archive` → `commit_push` may proceed.

## Remediation

- **Non-blocking wording nit (no action required for this task).** The CHANGELOG
  Changed entry says "`owl-orchestrator` and the `review_code` overlay now
  document...", but only the `owl-orchestrator` skill was edited; the project-local
  `.owl/overlays/review_code.md` was intentionally left untouched (it is an opt-out
  template, not a gem-seeded source, so the durable guidance lives in the
  propagating skill). The brief's AC reads "skills/owl-orchestrator / review
  overlay" (an OR), so this satisfies the AC. Optionally tighten the CHANGELOG line
  to name only the skill in a future pass — cosmetic, not gating.

## Residual risks

- The inline-literal branch of `--brief-body BODY` (a non-`-` value) and the
  `read_inline_brief_body` `rescue StandardError` are not exercised by tests. This
  is CLI-layer code, outside the `lib/owl/**/api.rb` 100% gate, and low risk
  (the documented/primary path is `-` for stdin). Acceptable.
- `owl upgrade` to refresh this repo's `.claude/skills/owl-*` from the edited seed
  sources is a deliberate post-merge propagation step, not part of this commit
  (flagged by the implementer).
