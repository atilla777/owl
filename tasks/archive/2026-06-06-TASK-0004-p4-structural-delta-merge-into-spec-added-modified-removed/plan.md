---
status: draft
summary: Checklist to build the spec/delta parsers + deterministic DeltaMerger + owl spec apply/diff CLI in Owl::Specs, re-validating before write, with determinism tests and 100% coverage on specs/api.rb.
---

# Goal

Ship a deterministic delta-merge engine (ADDED/MODIFIED/REMOVED Requirements) + `owl spec
apply/diff`, re-validating the merged spec before writing, with full tests and green gates.

# Checklist

1. **SpecDocument** — `lib/owl/specs/internal/spec_document.rb` (`module_function`):
   `parse(body) -> {frontmatter, preamble, requirements:[{name,heading,body}], tail}` (requirement
   spans to next `### `/`## `/EOF; name = trimmed text after `### Requirement:`). `serialize(model)`
   reconstructs byte-stably. Reuse heading semantics from
   `Owl::Validation::Internal::SectionScanner` (require it) rather than new regex. Round-trip
   (parse→serialize) of an untouched spec MUST be identity.

2. **SpecDelta** — `lib/owl/specs/internal/spec_delta.rb` (`module_function`):
   `parse(body) -> {added:[block], modified:[block], removed:[name]}` from the three
   `## ADDED|MODIFIED|REMOVED Requirements` sections. Errors → `invalid_delta` for: unknown
   `## X Requirements` heading, a name in >1 section, no operations at all.

3. **DeltaMerger** — `lib/owl/specs/internal/delta_merger.rb` (`module_function`):
   `apply(spec_model, delta) -> Result(model)`. Order REMOVED→MODIFIED→ADDED. Errors
   `delta_target_missing` (REMOVED/MODIFIED name absent), `delta_conflict` (ADDED name already
   present). Exact case-sensitive trimmed-name match. ADDED appended in delta order before `tail`.

4. **Unified-diff helper** — small in-process line-diff (`lib/owl/specs/internal/text_diff.rb` or
   inline) for human preview; dependency-free, deterministic.

5. **Create-from-absent** — when spec file missing + delta is ADDED-only, scaffold a minimal spec
   (frontmatter `status: draft`, `# Spec`, `## Purpose` placeholder, `## Requirements`) then apply.
   MODIFIED/REMOVED on missing spec → `spec_not_found`.

6. **Re-validate before write** — add a `validate_body`-style path: run the `spec` artifact type's
   rules against the merged body (write to the resolved spec path only AFTER validation passes; do
   merge+validate fully in memory; on invalid return `merge_would_invalidate` + violations, write
   nothing).

7. **Specs::Api** — add `diff(root:, domain:, delta_path:)` and `apply(root:, domain:, delta_path:,
   dry_run:false)` delegating to the internals; read the delta via `Storage::Api.read`
   (missing → `delta_not_found`); write via `Storage::Api.mkdir_p`+`write` on success only.
   Domain slug-validated (reuse SpecLocator). Keep `specs/api.rb` at 100% line coverage.

8. **CLI** — `lib/owl/cli/internal/commands/spec_apply.rb` + `spec_diff.rb` mirroring existing
   spec commands; positional `<domain>`, required `--delta PATH`, `--dry-run` (apply); JSON-first,
   `diff`/dry-run print preview + never write. Wire into `dispatch_spec`; update HELP_TEXT.

9. **Tests** — `spec/owl/specs/internal/{spec_document,spec_delta,delta_merger}_spec.rb` +
   `spec/owl/specs/apply_spec.rb` + CLI dispatch specs. Cover: each op happy path; conflict;
   target-missing; invalid-delta (unknown section, dup name, empty); dry-run/diff no-write;
   determinism (apply twice on same input ⇒ identical); round-trip identity; create-from-absent;
   merge_would_invalidate aborts write; block-boundary fixtures (adjacent requirements, trailing
   `## ` section, nested `####`).

10. **Gates** — `bundle exec rspec` green for touched areas + full-suite counts; confirm
    `specs/api.rb` 100% via simplecov; `bundle exec rubocop` clean on changed files (never `-A`).
    (If the suite dirties repo `README.md` via the known pre-existing isolation bug, restore with
    `git checkout README.md`.)

# Smoke test

```
bin/owl spec path demo --json
# Seed a spec, write a delta, then:
bin/owl spec apply demo --delta /tmp/d.md --dry-run --json   # preview, no write
bin/owl spec diff  demo --delta /tmp/d.md --json             # unified diff
bin/owl spec apply demo --delta /tmp/d.md --json             # writes; spec now contains ADDED req
bin/owl spec validate demo --json                            # still valid:true
bin/owl spec apply demo --delta /tmp/conflict.md --json      # ADDED existing -> delta_conflict, no write
bundle exec rspec spec/owl/specs spec/owl/cli
bundle exec rubocop lib/owl/specs lib/owl/cli/internal/commands/spec_apply.rb lib/owl/cli/internal/commands/spec_diff.rb lib/owl/cli/api.rb
# clean up throwaway specs/demo if created
```
