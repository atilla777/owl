---
status: resolved
summary: "Adversarial self-review of TASK-0009: hotfix/refactor spec_delta wiring + surgical flip_delta_status are correct; all gates green; no blocker/major findings"
---

# Summary

Adversarial self-review of TASK-0009. Scope: (a) optional `spec_delta` declared
in `.owl/workflows/{hotfix,refactor}/workflow.yaml`; (b) `merge_docs.context.md`
updated to run `owl publish` + `owl spec merge`; (c) `flip_delta_status` rewritten
as a surgical front-matter line edit in `lib/owl/specs/internal/task_merger.rb`;
(d) a doc-comment sentence on `merge_task`.

Verdict: the implementation is correct and matches the brief/design/plan. The
high-risk surgical string edit was probed live against ten hand-built deltas and
behaves exactly as specified. Seed-parity claim verified (hotfix/refactor are NOT
gem seeds, so there are no `workflows/` copies to sync). All declared gates are
green. No blocker or major findings; `status: resolved`.

# Findings

## F1 — Surgical flip_delta_status string edit (HIGH bug-surface) — NO BUG

Probed `rewrite_status_line` / `front_matter_with_merged_status` live (ruby
calling the internal) across the adversarial matrix:

- Extra/quoted/indented keys + a body `status:` mention (`- THEN status: ok`):
  ONLY the front-matter `status:` line flips to `status: merged`; every other
  front-matter line and the whole markdown body (including the body `status:`)
  byte-preserved. Front matter correctly scoped to the FIRST `---…---` block.
- No `status:` line in front matter: `status: merged` inserted INSIDE the block
  (before the closing `---`), not after it.
- Odd formatting normalized sanely to canonical `status: merged`: `status:draft`
  (no space), `status:  draft  ` (extra + trailing spaces), `status: "draft"`
  (quoted) — all re-parse and re-validate `valid:true`.
- Body thematic break (`\n---\n` later in body): scoped to the FM block; the body
  break preserved. FM closing at EOF with no trailing newline: handled.
- CRLF source, no-closing-fence source, and `---\n---\n` empty-FM source: return
  `nil` (no write, best-effort no-op) — CONSISTENT with `FrontMatterParser`,
  which uses the identical `rest.index("\n---\n") || rest.index("\n---")` fence
  detection and likewise does not recognize those as front matter. The "mirrors
  FrontMatterParser" comment is accurate.
- Idempotency: after a real merge the status is `merged`, so a re-run skips with
  `already_merged` (existing spec green).

Severity: HIGH surface, but no defect found. Resolution: verified-correct, no
change needed.

## F2 — Workflow wiring (hotfix/refactor) — NO BUG

`owl workflow validate hotfix|refactor` → both `valid:true`. Step graph unchanged
(8 steps; ids `brief design plan implement review_code merge_docs archive
commit_push`). The `spec_delta` artifact entry is byte-identical to feature's
(`type: spec_delta`, `optional: true`, storage role `tasks`, path
`{{task.id}}/spec_delta.md`), with no step creating it. `merge_docs.context.md`
for both differs from feature ONLY by the single "When to use" workflow-name line
(confirmed by `diff`). A throwaway hotfix task (fresh id TASK-0010 — allocator
fix confirmed, NOT TASK-0001) ran `owl spec merge` → `{ok:true, applied:false,
reason:"no_spec_delta"}`, wrote nothing under `specs/`; task deleted, tree clean.

Severity: none. Resolution: verified-correct.

## F3 — Seed-parity claim — CONFIRMED

`workflows/` contains only `feature` and `composite_feature`; `hotfix`/`refactor`
have no gem-seed copies, so there is nothing to sync. The seed-related suites
(`seeded_workflows_validate_spec.rb`, `seeded_sources_skill_bindings_spec.rb`)
pass. The verification report's documented deviation (no seed copies) is correct.

Severity: none. Resolution: claim accurate.

## F4 — FS-access / no_direct_fs — CLEAN

`flip_delta_status` reads/writes exclusively via `Owl::Storage::Api`; no raw
`File`/`Dir`/`Pathname` added in production code. The now-unused `require 'yaml'`
was correctly removed. The `constitution` suite (incl. no-direct-FS meta-spec)
is green.

Severity: none.

## F5 — Tests genuine — CONFIRMED

The two new specs assert real invariants (validate, 8-step graph + ids, optional
artifact shape, no creator; spec-less no-op writes nothing, context mentions both
commands). The idempotency additions assert byte-level preservation + re-validate.
Not hollow.

# Resolution

No blocker or major findings. Gates re-run (actual numbers):

- `bundle exec rspec spec/owl/specs spec/owl/workflows spec/owl/integration
  spec/owl/cli spec/owl/constitution` → 638 examples, 0 failures.
- `bundle exec rspec` (full) → 1415 examples, 0 failures, 1 pending (pre-existing
  storage backend concurrent-write pending, unrelated).
- Public-API coverage: only `lib/owl/steps/api.rb` 99.16% — pre-existing gap,
  untouched by this task.
- `bundle exec rubocop` on the 4 changed/added files → no offenses (no `-A` used).
- README.md was NOT dirtied by the suite; no `git checkout` needed.
- Throwaway TASK-0010 created and deleted; working tree holds only this task's
  own changes.

All findings resolved as verified-correct. `status: resolved`.
