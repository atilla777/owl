---
status: resolved
summary: Adversarial self-review of the P4 spec delta-merge engine — block-boundary, round-trip, determinism, merge semantics, write-safety, and FS-access all verified correct. Two minor by-design/cosmetic findings, no blockers. Full suite 1353 ex / 0 failures, specs/api.rb 100%, RuboCop clean, no_direct_fs green, README not dirtied.
---

# Summary

Reviewed the P4 implementation: a deterministic structural delta-merge engine
(`SpecDocument`, `SpecDelta`, `DeltaMerger`, `TextDiff`, `MergeEngine`) under
`lib/owl/specs/internal/`, `diff`/`apply` on `Owl::Specs::Api`, the `validate_body`
extraction in `artifact_runner.rb`, `expand_path` in `task_support.rb`, and the
`owl spec apply`/`owl spec diff` CLI. This is the highest bug-surface task to date
(parser + merge engine), so the review was adversarial: hand-built specs and deltas
exercising boundary conditions through the internal modules and the live CLI, not
just the shipped specs.

The implementation is correct on every probed axis. Block boundaries, round-trip
identity, determinism/idempotence, merge ordering and error semantics, write-safety,
`merge_would_invalidate`, create-from-absent, and the no-direct-FS constitution rule
all hold. No correctness defect was found. Two minor, non-blocking observations are
recorded below; both are consistent with the approved design.

# Findings

## Block-boundary correctness (HIGH RISK) — PASS, no finding

Hand-built adversarial probes through `SpecDocument.parse`, all with byte-identical
round-trip:
- (a) Two adjacent `### Requirement:` blocks → both parsed, neither swallows the other.
- (b) Requirement followed by a `## ` section → requirement bounded correctly; the
  `## ` section lands in `tail`.
- (c) `#### Scenario` and deeper `##### ` inside a requirement → level-4/5 headings do
  not end the block (boundary is level <= 3).
- (d) Title with trailing spaces / odd chars → `name` correctly trimmed (`"Weird Name"`).
- (e) `### Requirement:` inside a fenced code block → correctly NOT treated as a heading
  (fence-aware via `SectionScanner.code_line_mask`); only the real requirement parsed.

The design's reuse of `SectionScanner` for heading/fence semantics is the right call and
is what makes (e) safe.

## Round-trip identity — PASS, no finding

`serialize(parse(body)) == body` verified byte-for-byte for: canonical spec, no trailing
newline, CRLF line endings, multiple consecutive blank lines, frontmatter without a
closing fence, and empty body. Identity is structural — the parser slices the raw
`lines` array into contiguous non-overlapping ranges (preamble / requirement bodies /
tail) and `serialize` re-joins them, so `str.lines.join == str` guarantees identity for
any input, not just the template.

## Determinism / idempotence — PASS, no finding

`DeltaMerger.apply` is a pure function of `(spec_model, delta)`; applying the same delta
twice to the same input yields byte-identical output. Re-applying an ADDED delta to the
*output* correctly returns `delta_conflict` (the "twice on same INPUT" vs "apply output
again" distinction is handled correctly).

## Merge semantics — PASS, no finding

Verified through the internal modules and the live CLI:
- REMOVED → MODIFIED → ADDED canonical order.
- MODIFIED replaces in place (position preserved: `["A","B"]` stays `["A","B"]`).
- ADDED appended after existing requirements, before `tail`.
- Exact, case-sensitive name match (REMOVED `a` against `A` → `delta_target_missing`).
- MODIFIED/REMOVED of an absent requirement → `delta_target_missing`.
- ADDED of an existing requirement → `delta_conflict`.
- A name in two sections, an unknown `## X Requirements` heading, a delta with no
  operations, and a section with no requirement blocks → `invalid_delta`.

## Write-safety — PASS, no finding

`MergeEngine.prepare` performs all reads/merge/validation in memory; `Api.apply` writes
exactly once via `Storage::Api.mkdir_p` + `write` only on success and only when not
`dry_run`. Verified on the live CLI: `diff` and `apply --dry-run` against an absent
domain produced full previews but created NO file on disk; a real `apply` then created
it and `spec validate` returned `valid:true`. MODIFIED/REMOVED against a missing spec →
`spec_not_found`; missing delta file → `delta_not_found`.

## merge_would_invalidate — PASS, no finding

A MODIFIED requirement that drops its scenario was applied via the CLI: returned
`merge_would_invalidate` with the `requirement_without_scenario` violation, and the
on-disk spec's md5 was unchanged before/after (write aborted).

## FS-access / constitution — PASS, no finding

`grep` over `lib/owl/specs/**` for `File.`/`Dir.`/`Pathname`/`IO.` finds none; all I/O
is routed through `Owl::Storage::Api`. `expand_path` added to `task_support.rb` is pure
path-math (`Pathname#expand_path`, no I/O) and lives on the constitution path-utility
allowlist. The `no_direct_fs` meta-spec passes (10 examples, 0 failures).

## validate_body extraction — PASS, no finding

The change to `artifact_runner.rb` is a pure extraction: the body previously inline in
`validate` now lives in `validate_body`, and `validate` calls it with the read contents.
No behaviour change on the existing `validate` path; the full validation suite stays
green.

## Finding 1 (MINOR, cosmetic) — appended requirement heading has no preceding blank line

When the spec's last requirement (or the scaffold's `## Requirements` line) ends without
a trailing blank line, an ADDED requirement is glued directly onto the next line, e.g.
`- THEN y\n### Requirement: B` or `## Requirements\n### Requirement: Probe`. The output
is still valid and stable: `SectionScanner` is line-based and detects the heading
regardless, merged-spec validation returns `valid:true`, and round-trip/idempotence
hold (CommonMark ATX headings may interrupt paragraphs, so external renderers also treat
it as a heading). Purely a readability nit, not a correctness defect.

## Finding 2 (MINOR, by-design limitation) — non-contiguous requirements fold into tail

A `### Requirement:` that appears after an intervening `## ` section (i.e. not in the
first contiguous run of requirement blocks) is absorbed into `tail` and is therefore not
targetable by MODIFIED/REMOVED/ADDED. This matches the documented design ("tail is
everything after the last contiguous requirement block") and the canonical grammar where
requirements are the final section, so it does not affect well-formed specs.

# Resolution

- Block-boundary, round-trip, determinism, merge semantics, write-safety,
  merge_would_invalidate, FS-access, and validate_body: verified correct, no action.
- Finding 1 (cosmetic blank line): NOT fixed. It is not a correctness bug — output is
  valid, deterministic, and round-trip-stable, and the current byte output is encoded in
  the test suite. Fixing it would churn tested fixtures for a pure aesthetic gain;
  recorded as an optional follow-up (a serializer-level blank-line normalization).
  Severity: minor / nit.
- Finding 2 (non-contiguous requirements): NOT changed — it is the approved design and
  matches the spec grammar. Recorded as a documented limitation; if specs ever interleave
  requirements with other `## ` sections, the parser would need a requirements-section
  scope. Severity: minor / by-design.
- Gates (actual numbers): full suite 1353 examples, 0 failures, 1 pending; targeted
  `spec/owl/specs spec/owl/cli spec/owl/validation spec/owl/constitution` = 474 examples,
  0 failures; `lib/owl/specs/api.rb` at 100% line coverage (only pre-existing
  `lib/owl/steps/api.rb` 99.16% remains, unrelated); RuboCop 21 files, no offenses (no
  `-A` used); `no_direct_fs` meta-spec 10 examples, 0 failures. README.md was NOT dirtied
  this run; throwaway `specs/zzthrowaway` and `/tmp` deltas created during probing were
  removed.

No blocker or major finding is open ⇒ `status: resolved`.
