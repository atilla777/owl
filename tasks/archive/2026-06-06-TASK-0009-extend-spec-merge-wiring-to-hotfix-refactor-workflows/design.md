---
status: approved
summary: "Mirror feature's spec_delta artifact declaration + merge_docs context into hotfix/refactor (active + seed), make flip_delta_status a surgical status-line rewrite via a small front-matter line edit, and add one doc sentence to merge_task — all backward-compatible."
---

# Context

TASK-0007 added to the `feature` workflow: an optional `spec_delta` entry in the `artifacts:` map
(`type: spec_delta`, storage role `tasks`, path `{{task.id}}/spec_delta.md`, no creating step) and
a `merge_docs.context.md` that instructs running `owl publish` AND `owl spec merge`, both no-ops
when nothing applies. `hotfix` and `refactor` (`.owl/workflows/{hotfix,refactor}/` + seed
`workflows/{hotfix,refactor}/`) have the identical 8-step structure incl. a `merge_docs` step and
context file, but lack both additions. The `spec_delta` artifact TYPE is already registered
globally, so no new type work is needed. TASK-0008's `flip_delta_status`
(`lib/owl/specs/internal/task_merger.rb`) currently splits front matter via FrontMatterParser and
re-dumps the whole hash with `YAML.dump`, which can reformat unrelated keys.

# Decision

**1. Wire hotfix + refactor (parity with feature).**
- Add the same `spec_delta` artifact entry to `.owl/workflows/hotfix/workflow.yaml`,
  `.owl/workflows/refactor/workflow.yaml`, and their seed copies under `workflows/...`.
- Replace `.owl/workflows/{hotfix,refactor}/merge_docs.context.md` (+ seed) with the feature
  merge_docs context content (the version that documents `owl publish` + `owl spec merge` and the
  `no_publishable_step`/`no_spec_delta` no-ops), adjusting only workflow-name references if any.
- Keep active and seed copies byte-identical.

**2. Surgical `flip_delta_status`.** Replace the whole-hash re-dump with a line-level rewrite of the
front-matter block:
- Read the delta body; locate the leading `---\n ... \n---` front-matter block.
- Within it, if a `^status:` line exists, replace ONLY that line's value with `merged` (preserve
  the key's surrounding whitespace/quoting style of the value minimally — emit `status: merged`).
- If no `status:` line exists, insert `status: merged` as a new line at the end of the front-matter
  block.
- Leave every other front-matter line and the markdown body byte-for-byte unchanged.
- Re-validate the rewritten delta parses (FrontMatterParser) and still validates against the
  `spec_delta` type in tests. Keep all FS access via `Storage::Api`.

**3. Doc sentence on merge_task.** Add one sentence to the `TaskMerger`/`merge_task` doc comment:
on a gate-fail the merged spec is persisted AND the delta `status` is flipped to `merged`, so a
re-run skips (`already_merged`) rather than re-applying; `owl spec trace --strict` remains the
authoritative coverage gate.

# Alternatives

- **Make spec_delta a required artifact in hotfix/refactor** — rejected: same reasoning as feature;
  optional + graceful skip keeps these workflows' default behaviour unchanged.
- **Share one merge_docs context across workflows** — out of scope: the repo keeps per-workflow
  context files; duplicating the proven feature content is lowest-risk and matches the layout.
- **Leave flip_delta_status re-dumping** — rejected: cosmetic but the tool should make minimal,
  predictable edits to user-authored delta files; a surgical line edit is the right behaviour.
- **Regex-replace the status anywhere in the body** — rejected: must scope to the front-matter
  block so a `status:` mention in the markdown body is never touched.

# Risks

- **Seed/active drift** for two workflows × (workflow.yaml + merge_docs.context.md) — mitigated:
  update all copies; the seed-parity / template-skeleton suite guards them; assert byte-identical.
- **Surgical edit corrupting front matter** (e.g. multi-doc `---` in body, no trailing newline) —
  mitigated: operate only on the FIRST `---`…`---` block; tests cover extra keys, missing status,
  quoting/indentation preservation, and re-parse/re-validate.
- **Workflow validator rejecting the optional artifact** — already proven to accept it for feature
  (TASK-0007); covered by `owl workflow validate hotfix|refactor` tests.
- **No api.rb touched** — `flip_delta_status` is internal; coverage gate unaffected beyond the
  pre-existing `steps/api.rb` note.

# API

No public API signature change. `Owl::Specs::Internal::TaskMerger#flip_delta_status` becomes a
surgical front-matter line edit (same inputs/outputs). hotfix + refactor workflows gain the optional
`spec_delta` artifact and updated merge_docs context. Doc-comment-only change on `merge_task`.
Behaviour for spec-less tasks is unchanged across all three workflows.
