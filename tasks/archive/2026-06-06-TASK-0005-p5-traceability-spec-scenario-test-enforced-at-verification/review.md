---
status: resolved
summary: "P5 scenario->test traceability self-review: parser/classification/strict semantics all correct under adversarial probing; two minor design observations (path-traversal via `..`, requirement-with-zero-scenarios not flagged) surfaced as non-blocking follow-ups; template dangling demo ref judged acceptable. Gates green."
---

# Summary

Adversarial self-review of P5 (scenario->test traceability): `Owl::Specs::Internal::TraceChecker`,
`Owl::Specs::Api.trace`, the `owl spec trace` CLI, the `- TEST:` section in `docs/agents/31`, and the
seeded `- TEST:` line in the active + seed spec templates.

I hand-built specs through the internal modules and exercised the live CLI. The scenario-split,
TEST-extraction regex, ref classification, `--strict`/`ok`, read-only and determinism behaviours are
all correct. No blocker or major findings. Two minor design observations are recorded as follow-ups
(no code change — both are defensible as-is). The template's dangling demo ref is judged acceptable.

Gate results (actual): `bundle exec rspec spec/owl/specs spec/owl/cli spec/owl/constitution` =>
391 examples, 0 failures; `bundle exec rubocop` on the 8 changed lib+spec files => no offenses;
`spec/owl/constitution` (incl. no_direct_fs meta-spec) => 10 examples, 0 failures;
`lib/owl/specs/api.rb` line coverage = 100% (59/59). README.md not dirtied.

# Findings

## Correctness probes (all PASS)

- **Scenario split (cases a-e).** Verified directly against `TraceChecker.trace`:
  - (a) two adjacent `#### Scenario:` under one requirement — TEST lines attributed to the right
    scenario (Alpha=traced, Beta=dangling), no bleed.
  - (b) scenario followed by a deeper `##### ` heading — TEST under the level-5 heading still
    attributed to the enclosing scenario (level 5 > SCENARIO_LEVEL=4, not a boundary).
  - (c) `#### Scenario:` inside a fenced code block — NOT counted (SectionScanner is fence-aware;
    `test_refs` also skips masked lines). summary scenarios=1.
  - (d) requirement with no scenarios — produces `scenarios: []`, contributes nothing.
  - (e) `- TEST:` in a requirement preamble (before the first scenario) — correctly ignored, not
    miscounted; a `..`-free preamble ref to a non-existent file did NOT surface as dangling.
- **TEST regex `/^[\s>*-]*\**\s*TEST:\s*(.+?)\s*$/`.** Matches `- TEST:`, `* TEST:`, `  - TEST:`,
  `**TEST:**` (closing bold stripped by `clean_ref`), bare `  TEST:`. Correctly does NOT match the
  prose `the TEST: was run`, `- THEN the TEST: foo`, or a `#### Scenario: TEST:` heading (`#` is not
  in the leading char class; heading lines are also excluded from the scan range). No false matches.
- **Classification.** `spec/owl/present_spec.rb` (exists) => traced; missing path => dangling;
  prose/id (no `/`) => unverified (counts valid). Existence goes through
  `Owl::Storage::Api.exists?` on a `"#{root}/#{ref}"` path, not raw `File`.
- **valid / --strict / ok.** valid = no untraced AND no dangling (unverified stays valid);
  `ok = strict ? valid : true`. Confirmed live: non-strict `ok:true` on a dangling spec; `--strict`
  flips `ok:false` (exit 1) on both untraced and dangling. Zero-requirement spec => vacuously valid.
- **Read-only.** Trace writes nothing — Api/CLI specs assert mtime + `specs/**` entry-set unchanged;
  absent domain => `spec_not_found` with no file created.
- **FS-access.** `grep -E '\b(File|Dir|Pathname|IO)\b\.'` over the new `lib/owl/specs/**` +
  `spec_trace.rb` + `specs/api.rb` => none. no_direct_fs meta-spec green.
- **Determinism.** Report is in document order; two runs produce `==` reports.
- **Template / docs.** Active `.owl/artifacts/spec/templates/default.md` and seed
  `artifacts/spec/templates/default.md` are byte-identical. Seeded template `owl spec validate`s
  clean (the `- TEST:` bullet is an extra list item, not a WHEN/THEN, so `require_when_then` is
  unaffected). Doc 31 §3a accurately describes syntax, classification, and that enforcement is
  `owl spec trace --strict` (not authoring-time).

## Observation 1 — path-like ref with `..` escapes the project root (minor)

`path_like?` only requires `/` + a `.<ext>` tail; existence is `Owl::Storage::Api.exists?(path:
"#{root}/#{ref}")` with no normalization. A ref like `- TEST: ../secret.rb` resolves to
`root/../secret.rb` and, if such a file exists ANYWHERE reachable, the scenario is marked `traced`.
Probed and reproduced. The design text says existence is checked "under the project root", so `..`
escaping that is a slight deviation. Impact is low: refs are team-authored spec content, the check
is a read-only `exists?` boolean (no content disclosure, no write), and the only consequence is an
inflated `traced` verdict. Not fixed in-line because a `..` guard could create false NEGATIVES for
legitimate monorepo layouts where shared tests live above the spec root — a genuine design trade-off
worth a deliberate decision rather than a silent self-review change.

## Observation 2 — a requirement with zero scenarios is not flagged by `trace` (minor)

`valid` is driven solely by untraced scenarios + dangling refs. A `### Requirement:` with NO
`#### Scenario:` yields `scenarios: []` and `valid:true` (probed, case d). The requirement->scenario
link is delegated to P3's authoring-time `require_scenarios`; the brief's `--strict` contract only
mentions "untraced scenario", so this is consistent with the stated design. Worth noting that if a
spec type has `require_scenarios` disabled, a scenario-less requirement passes `owl spec trace
--strict` silently. Non-blocking; surfaced for a future decision on whether trace should also flag
scenario-less requirements.

## Verdict — template dangling demo ref (`- TEST: spec/example/example_spec.rb`)

Kept as-is. Live `owl spec trace` on a fresh-project copy of the template reports this as `dangling`
(strict => exit 1). Considered switching to a non-path placeholder (=> `unverified`, valid:true), but
rejected it: `unverified` would give a misleading false-green on a scaffold that has no real test,
whereas `dangling` is the honest signal ("point this at a real test") and the path form demonstrates
the canonical, recommended convention. The whole "Example capability" requirement is fill-in
scaffold content. No change.

# Resolution

- Correctness probes (scenario split a-e, regex, classification, strict/ok, read-only, FS-access,
  determinism, template/doc): PASS — no action.
- Observation 1 (path traversal via `..`): severity minor — recorded as an open follow-up; no code
  change (defensible both ways; avoid breaking legit `..` monorepo refs).
- Observation 2 (zero-scenario requirement not flagged): severity minor — recorded as an open
  follow-up; consistent with the documented design (delegated to `require_scenarios`).
- Template demo ref: resolved (kept; honest `dangling` signal preferred over false-green).
- Gates: `rspec` 391/0, `rubocop` 0 offenses, constitution 10/0, `specs/api.rb` 100% coverage,
  README.md clean. Throwaway smoke project under `/tmp` removed; no `specs/<domain>` left in repo.

No blocker or major findings remain open, so status is `resolved`.
