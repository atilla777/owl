---
status: draft
summary: "Checklist to mirror feature's spec_delta artifact + merge_docs context into hotfix/refactor, make flip_delta_status a surgical front-matter line edit, and add a merge_task doc sentence, with tests and green gates."
---

# Goal

Bring hotfix/refactor to spec-layer parity with feature and apply two polish items, all
backward-compatible, with tests and green gates. No public API change.

# Checklist

1. **Declare spec_delta in hotfix + refactor (active + seed)** — add to
   `.owl/workflows/hotfix/workflow.yaml`, `.owl/workflows/refactor/workflow.yaml`, and seed copies
   `workflows/hotfix/workflow.yaml`, `workflows/refactor/workflow.yaml` an `artifacts:` entry
   `spec_delta: {type: spec_delta, storage: {role: tasks, path: "{{task.id}}/spec_delta.md"}}`,
   matching feature's exactly, with NO step creating it. Run `bin/owl workflow validate hotfix` and
   `... refactor` → both `valid:true`.

2. **Update merge_docs context (active + seed)** — copy the feature `merge_docs.context.md` content
   (the `owl publish` + `owl spec merge` version with no-op semantics) into
   `.owl/workflows/{hotfix,refactor}/merge_docs.context.md` and seed `workflows/...`. Adjust only
   workflow-name references if present. Keep active and seed byte-identical (diff to confirm).

3. **Surgical flip_delta_status** — in `lib/owl/specs/internal/task_merger.rb`, rewrite
   `flip_delta_status` to edit only the front-matter `status:` line: isolate the first
   `---\n...\n---` block; if a `^status:` line exists, replace its value with `merged`; else insert
   `status: merged` at the block's end. Preserve all other lines + the body byte-for-byte. Write via
   `Storage::Api.write`. Keep dry-run from flipping (unchanged call site).

4. **merge_task doc sentence** — add one sentence to the `TaskMerger` module / `merge_task` doc
   comment: on a gate-fail the spec is persisted AND the delta `status` flips to `merged`, so a
   re-run skips (`already_merged`); `owl spec trace --strict` is the authoritative gate.

5. **Tests** —
   - `spec/owl/workflows/hotfix_refactor_spec_delta_spec.rb`: `owl workflow validate hotfix|refactor`
     valid; step graph unchanged (8 steps, ids intact); `spec_delta` present in the artifacts map.
   - `spec/owl/integration/hotfix_refactor_merge_docs_spec.rb` (or extend an existing integration
     spec): a spec-less hotfix/refactor task → `owl spec merge` returns `no_spec_delta`, no writes.
   - Extend `spec/owl/specs/merge_task_idempotency_spec.rb`: a delta with EXTRA front-matter keys +
     specific quoting/indent → after flip only `status` changes (other keys byte-preserved), result
     re-parses + validates; a delta with NO `status:` line → `status: merged` appended.
   - Existing TASK-0007/0008 merge/trace + seed-parity specs stay green.

6. **Seed parity** — keep active `.owl/` and seed `workflows/` copies in sync; the seed-parity /
   template-skeleton suite must stay green.

7. **Gates** — `bundle exec rspec` green for touched areas + full-suite counts; `bundle exec rubocop`
   clean on changed files (never `-A`). If the suite dirties `README.md` (known pre-existing
   isolation bug), `git checkout README.md`. Clean up any throwaway `specs/<domain>` / tasks.

# Smoke test

```
bin/owl workflow validate hotfix && bin/owl workflow validate refactor   # both valid:true
# spec-less no-op via the same command merge_docs would run:
#   (create a throwaway hotfix task) bin/owl spec merge TASK-XXXX --json -> reason: no_spec_delta
# surgical flip: craft a spec_delta with extra keys, run owl spec merge, diff the delta file
#   -> only the status: line changed
diff .owl/workflows/hotfix/merge_docs.context.md workflows/hotfix/merge_docs.context.md   # identical
bundle exec rspec spec/owl/workflows spec/owl/specs spec/owl/integration
bundle exec rubocop lib/owl/specs/internal/task_merger.rb
```
