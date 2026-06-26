---
status: approved
summary: Purge 9 dead owl-step-run refs across 5 skill/command files and make owl-author Q6 bind steps by session_type.
---

# Plan

## Goal

Remove every `owl-step-run` reference from the skills/commands tree and make
`/owl-author` (Mode A Q6) emit `session_type`-correct step bindings
(`owl-step-discussion` for `discussion`, `owl-step-execution` for `execution`),
so authored workflows match the seeded ones. Bump `Owl::VERSION` (patch) and add
a CHANGELOG entry because `skills/**` and `commands/**` are consumer-materialized.

## Scope

- `skills/owl-init/SKILL.md` — 1 ref (line ~111).
- `skills/owl-cli/SKILL.md` — 4 refs (lines ~11, 32, 110, 135).
- `skills/owl-author/SKILL.md` — 2 refs (line ~29 prose; line ~61 the functional binding rule).
- `skills/owl-orchestrator/SKILL.md` — 1 ref (line ~84).
- `commands/owl-task-next.md` — 1 ref (line ~8).
- `lib/owl/version.rb` + `CHANGELOG.md` — version bump + entry.

## Constraints

- SKILL.md bodies are the canonical English contract (constitution 5.16) — keep prose English.
- Preserve the "unless the user names a different `owl-step-<x>` skill explicitly" escape hatch in owl-author Q6 (brief edge case: custom step skills preserved verbatim).
- No `bin/owl` CLI/JSON contract change; this is documentation + authoring-instruction only.

## Files to inspect

- `.owl/workflows/feature/workflow.yaml` (already confirmed: every step has `session_type:` + matching `skill:`) — the shape Q6 must reproduce.
- `skills/owl-step-discussion/SKILL.md`, `skills/owl-step-execution/SKILL.md` (the two real targets).

## Checklist

- [ ] `skills/owl-init/SKILL.md` ~L111: replace `owl-step-run` with `owl-step-discussion`/`owl-step-execution` in the downstream-skills list.
- [ ] `skills/owl-cli/SKILL.md` ~L11: replace `owl-step-run` in the "called from other Owl-owned skills" list with the two step skills.
- [ ] `skills/owl-cli/SKILL.md` ~L32: replace "belong to the orchestrator and to `owl-step-run`" with the two step skills.
- [ ] `skills/owl-cli/SKILL.md` ~L110: update the `owl init` materialise description — seeded skills are `owl-step-discussion`/`owl-step-execution` (not `owl-step-run`); each step bound to its `session_type` skill.
- [ ] `skills/owl-cli/SKILL.md` ~L135: replace "preferred for `owl-step-run`" with the step skills.
- [ ] `skills/owl-author/SKILL.md` ~L29: replace "use `owl-step-run` instead" with `owl-step-discussion`/`owl-step-execution`.
- [ ] `skills/owl-author/SKILL.md` ~L61 (Q6 — the functional fix): add a `session_type` question (`discussion | execution`) and change the auto-fill rule to bind `skill: owl-step-discussion` when `session_type: discussion` and `skill: owl-step-execution` when `session_type: execution`, unless the user names a different `owl-step-<x>` skill explicitly.
- [ ] `skills/owl-orchestrator/SKILL.md` ~L84: replace the `owl-step-run` example in the stop-condition with `owl-step-execution` (the execution-step skill).
- [ ] `commands/owl-task-next.md` ~L8: replace "delegates to `owl-step-run`" with "delegates to `owl-step-discussion`/`owl-step-execution` by `session_type`".
- [ ] `lib/owl/version.rb`: bump patch.
- [ ] `CHANGELOG.md`: add an entry under a new version heading.
- [ ] Re-materialize this repo's `.claude/` from `skills/owl-*` if the orchestrator/author/cli/init/task-next copies under `.claude/` are stale (`bin/owl upgrade` / `init --force`), or note it for the merge_docs/commit steps.

## Tests and verification

- `grep -rn owl-step-run skills/ commands/` → 0 matches (primary acceptance criterion).
- `grep -rn owl-step-run .claude/` → 0 matches after re-materialize (consumer-facing copy).
- owl-author Q6 text names `session_type` and binds both step skills (manual read; no Ruby spec — owl-author is instruction markdown, not code).
- `bundle exec rspec` stays green (no Ruby behavior changed).

## Smoke test

`grep -rn owl-step-run skills/ commands/ .claude/commands .claude/skills` returns nothing, and `skills/owl-author/SKILL.md` Q6 shows the `session_type`-driven binding rule.

## Out of scope

- Renaming or merging the `owl-step-discussion` / `owl-step-execution` skills.
- Any change to the seeded workflow YAMLs (they already bind correctly).
- Adding a Ruby-level enforcement of step→skill binding (owl-author is agent instructions, not validated code).
