---
status: draft
summary: "Checklist to register the spec_delta artifact, add owl spec merge (P4 apply + P5 trace gate, graceful skip), and wire merge_docs — backward-compatible, fully tested, 100% on specs/api.rb."
---

# Goal

Connect the P4 delta-merge + P5 trace engines into the feature workflow via an optional spec_delta
artifact and a deterministic `owl spec merge`, invoked by merge_docs, with no behavioural change
for spec-less tasks.

# Checklist

1. **spec_delta artifact type** — scaffold via `bin/owl artifact-type new spec_delta` then edit
   active `.owl/artifacts/spec_delta/{artifact.yaml,templates/default.md}` AND the repo-root seed
   `artifacts/spec_delta/...`. front matter: required `domain` + `status` (enum draft|merged).
   `validation.required_patterns`: one entry mandating `(?m)^## (ADDED|MODIFIED|REMOVED) Requirements`.
   Template seeds `domain`, a `## ADDED Requirements` with `### Requirement:` + `#### Scenario:`
   (WHEN/THEN/`- TEST:`). Register in `.owl/artifacts.yaml` + seed `artifacts.yaml`. Confirm
   `bin/owl artifact-type validate spec_delta` passes.

2. **Declare spec_delta optional in feature workflow** — add to `.owl/workflows/feature/
   workflow.yaml` (+ seed) `artifacts:` map: `spec_delta: {type: spec_delta, storage: {role: tasks,
   path: "{{task.id}}/spec_delta.md"}}`, with NO step `creates:` it. Run `bin/owl workflow validate
   feature`; if it rejects an artifact lacking a creating step, instead add
   `uses_if_present: [spec_delta]` to the merge_docs step. Pick whichever validates.

3. **TaskMerger internal** — `lib/owl/specs/internal/task_merger.rb` (`module_function`):
   `merge(root:, task_id:, dry_run:)`. Resolve spec_delta path (Artifacts::Api.resolve or storage
   `tasks/<id>/spec_delta.md`); absent → `{applied:false, reason:'no_spec_delta'}`. Parse front
   matter `domain` (missing → `spec_delta_missing_domain`; slug-invalid via SpecLocator →
   `invalid_domain`). Apply via `Specs::Api.apply(root:, domain:, delta_path:, dry_run:)`. Trace via
   `Specs::Api.trace(root:, domain:, strict:true)`. Return `{ok: trace.valid, applied:!dry_run,
   domain:, merge:, trace:}`.

4. **Specs::Api.merge_task** — add to `lib/owl/specs/api.rb` (public, keep 100% cov) delegating to
   TaskMerger. Exercise ok/skip/dry-run/missing-domain/gate-fail through Api+CLI for coverage.

5. **CLI spec_merge** — `lib/owl/cli/internal/commands/spec_merge.rb`: positional `<TASK-ID>`,
   `--dry-run`, `--json`; non-JSON prints apply+trace summary. Wire into `dispatch_spec`
   (`lib/owl/cli/api.rb`); update `lib/owl/cli/internal/help_text.rb`.

6. **Wire merge_docs** — update `.owl/workflows/feature/merge_docs.context.md` (+ seed) to instruct
   the executor to run `owl publish TASK-ID` AND `owl spec merge TASK-ID`, treating `no_spec_delta` /
   `no_publishable_step` as normal no-ops and requiring the trace gate to pass when a delta is
   present. Document the spec-less no-op behaviour.

7. **Tests** — `spec/owl/specs/internal/task_merger_spec.rb`, `spec/owl/specs/merge_task_spec.rb`
   (Api), `spec/owl/cli/spec_merge_command_spec.rb`, and
   `spec/owl/integration/merge_docs_spec_merge_spec.rb` (or extend an existing workflow integration
   spec) asserting a spec-less task's merge is a clean no-op. Cover: apply+trace ok; gate failure
   (untraced) → ok:false with delta still applied; no-delta skip; dry-run no-write; missing-domain;
   propagated delta errors. Confirm `bin/owl workflow validate feature` still passes and
   `bin/owl artifact-type validate spec_delta` passes.

8. **Seed parity** — keep active `.owl/` and seed `artifacts/` + workflow copies in sync; the
   seed-parity / template-skeleton suite must stay green.

9. **Gates** — `bundle exec rspec` green for touched areas + full-suite counts; `specs/api.rb` 100%
   via simplecov; `bundle exec rubocop` clean on changed files (never `-A`). If the suite dirties
   `README.md` (known pre-existing isolation bug), `git checkout README.md`.

# Smoke test

```
# Seed a domain spec, create a task with tasks/<id>/spec_delta.md (domain + ADDED Requirement w/ TEST):
bin/owl spec merge TASK-XXXX --dry-run --json   # preview apply+trace, no write
bin/owl spec merge TASK-XXXX --json             # applies delta + trace gate
bin/owl spec validate <domain> --json           # still valid
# A task with no spec_delta:
bin/owl spec merge TASK-YYYY --json             # {ok:true, applied:false, reason:"no_spec_delta"}
bin/owl artifact-type validate spec_delta && bin/owl workflow validate feature
bundle exec rspec spec/owl/specs spec/owl/cli spec/owl/integration
bundle exec rubocop lib/owl/specs lib/owl/cli/internal/commands/spec_merge.rb lib/owl/cli/api.rb
# clean up throwaway specs/<domain> + tasks
```
