---
status: passed
summary: "hotfix/refactor wired to spec_delta + merge_docs; flip_delta_status made surgical; merge_task doc clarified — all gates green"
---

# Summary

Brought the `hotfix` and `refactor` workflows to spec-layer parity with `feature` and applied the
two polish items from the plan:

1. Declared the optional `spec_delta` artifact in `hotfix` and `refactor` workflows.
2. Updated their `merge_docs.context.md` to the feature `owl publish` + `owl spec merge` version
   (no-op semantics), adjusting only the workflow-name reference.
3. Rewrote `flip_delta_status` as a surgical, line-level front-matter edit (replace the first
   `status:` line in place, or append `status: merged` when absent) that preserves every other
   front-matter line and the markdown body byte-for-byte. All FS via `Storage::Api`.
4. Added a doc sentence to the `TaskMerger` doc comment about the gate-fail status flip.

Deviation from the plan (documented): the plan assumed seed copies under
`workflows/hotfix/` and `workflows/refactor/`. Those do NOT exist — only `feature` and
`composite_feature` are part of the gem seed (`SEEDED_WORKFLOW_KEYS`). `hotfix`/`refactor` are
project-local control-plane workflows that live ONLY under `.owl/workflows/`. So only the active
`.owl/` copies were edited; there are no seed copies to keep byte-identical. The active copies were
verified byte-identical to feature except the single "When to use" workflow-name line.

# Commands

- `bin/owl workflow validate hotfix --json` -> `{"ok":true,"valid":true,"id":"hotfix"}`
- `bin/owl workflow validate refactor --json` -> `{"ok":true,"valid":true,"id":"refactor"}`
- `diff .owl/workflows/feature/merge_docs.context.md .owl/workflows/hotfix/merge_docs.context.md`
  -> only line 18 differs (`feature` -> `hotfix`); refactor likewise (`feature` -> `refactor`).
- `bundle exec rspec spec/owl/workflows/hotfix_refactor_spec_delta_spec.rb spec/owl/integration/hotfix_refactor_merge_docs_spec.rb spec/owl/specs/merge_task_idempotency_spec.rb spec/owl/specs/internal/task_merger_spec.rb`
  -> 19 examples, 0 failures.
- `bundle exec rspec` (full suite) -> 1415 examples, 0 failures, 1 pending.
- `bundle exec rubocop lib/owl/specs/internal/task_merger.rb spec/owl/specs/merge_task_idempotency_spec.rb spec/owl/workflows/hotfix_refactor_spec_delta_spec.rb spec/owl/integration/hotfix_refactor_merge_docs_spec.rb`
  -> 4 files inspected, no offenses detected.

# Outcomes

- Both `hotfix` and `refactor` validate `valid:true`; 8-step graphs and step ids unchanged;
  `spec_delta` present in each artifacts map (optional, tasks role, `{{task.id}}/spec_delta.md`),
  with no creating step.
- Active `.owl/workflows/{hotfix,refactor}/merge_docs.context.md` are byte-identical to the feature
  template except the single workflow-name reference line.
- Surgical `flip_delta_status`: the idempotency spec asserts a delta with extra front-matter keys
  (quoted value with a colon, nested list, single-quoted value) flips ONLY the `status` line — the
  whole file equals the original with just `status: draft` -> `status: merged`, body byte-preserved,
  and re-validates `valid:true`. A delta with no `status:` line gets `status: merged` appended at the
  end of the front-matter block and re-validates. Dry-run still does not flip (existing spec green).
- Full suite: 1415 examples, 0 failures, 1 pending. The only public-API coverage gap is the
  pre-existing `lib/owl/steps/api.rb` 99.16% (untouched here).
- README.md was NOT dirtied by the suite (no `git checkout` needed). No throwaway files left; the
  only working-tree task-state changes are this task's own `tasks/TASK-0009/` artifacts and
  `tasks/index.yaml`.
