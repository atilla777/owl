---
status: resolved
verdict: accepted
summary: "Independent review of TASK-0033 GitRunner cleanup. The dead publics `status_porcelain` and `add_all` are genuinely unreferenced (grep over lib/ + spec/ = 0; nothing called them after TASK-0032 moved commit-push to scoped staging) and were removed safely. `index_dirty?` → `index_clean?` is a pure rename: the body is byte-identical (`git diff --cached --quiet`), the single caller `Transaction#index_empty?` reads `.ok` exactly as before, and `Outcome.ok = git success` (ok ⇔ empty/clean index) semantics are preserved — so the guard/retry/staging behavior is identical to post-TASK-0032. grep for the three old names over lib/+spec/ returns 0 (remaining hits live only in CHANGELOG history + task/docs markdown, untouched). Full suite 1972 examples / 0 failures / 1 pre-existing pending, exit 0; rubocop net-zero on all 5 touched files; commit_push/api.rb unchanged and still 100% line coverage (public-API gate). patch bump 0.17.0→0.17.1 + CHANGELOG entry are correct for an internal, no-behavior-change cleanup. Verdict: accepted."
---

# Summary

Independent, adversarial review of TASK-0033 — a small follow-up cleanup of
`Owl::CommitPush::Internal::GitRunner` after TASK-0032. Two concerns: (1) the two
public methods removed (`status_porcelain`, `add_all`) must be truly dead — no
production callers, no tests — and (2) the `index_dirty?` → `index_clean?`
rename must be a pure rename with identical behavior, leaving no dangling
references and not perturbing the commit-push guard/retry/staging logic.

I re-derived every focus point from the diff and the surrounding code, ran the
old-name grep over both `lib/` and `spec/`, and ran the full suite + RuboCop +
per-file coverage. No defects found. Verdict: **accepted**.

Production changes reviewed:
- `lib/owl/commit_push/internal/git_runner.rb` — removed `add_all` and
  `status_porcelain`; renamed `index_dirty?` → `index_clean?` (body unchanged:
  `run(['git', 'diff', '--cached', '--quiet'], root)`); reworded the `add_scoped`
  comment to drop the now-defunct `add_all` reference.
- `lib/owl/commit_push/internal/transaction.rb` — the one caller,
  `index_empty?`, now reads `git.index_clean?(root: root).ok` (was
  `git.index_dirty?(...).ok`).
- `lib/owl/version.rb` 0.17.0→0.17.1, `CHANGELOG.md` `[0.17.1]`.
- Specs: `git_runner_spec.rb` (describe block + 2 calls renamed), `api_spec.rb`
  (fake_git key + 3 scenario overrides + a comment), `locking_spec.rb`
  (object_double key).

# Findings

All five review-focus points checked; each confirmed by code, grep, and/or the
test run.

1. **No dangling references — OK.** `grep -rn "index_dirty?\|status_porcelain\|add_all" lib/ spec/`
   returns nothing (exit 1, zero matches). The broader repo grep finds the old
   names only in `CHANGELOG.md` (the new 0.17.1 entry naming what was removed,
   plus history), in `tasks/`/`docs/` markdown (design/plan/brief prose and the
   TASK-0016/0032 archives), and never in runnable `.rb` code. Those are
   historical and out of scope — correctly untouched.

2. **Behavior unchanged — OK.** `index_clean?` is byte-for-byte the prior
   `index_dirty?` implementation (`git diff --cached --quiet`), only the method
   name and the comment's trailing word changed. The sole caller
   `Transaction#index_empty?` consumes `.ok` exactly as before, so the
   empty-delivery guard and the idempotent-retry predicate fire on identical
   conditions. `Outcome.ok = status.success?` (git exit 0 ⇒ ok=true ⇒ index
   empty/clean) is preserved — the runner still returns raw git success and the
   caller interprets it. Guard/retry/scoped-staging behavior is identical to the
   post-TASK-0032 state.

3. **Removed methods were genuinely dead — OK.** Neither `status_porcelain` nor
   `add_all` had any caller in `lib/` or `spec/` (grep = 0), and neither had a
   dedicated test. They were already flagged as unreferenced in the TASK-0032
   review (its residual-risks section: "Dead facade methods … now unused (0
   coverage)"). `add_all` was superseded by `add_scoped` (whose empty-exclude
   branch is the same `git add -A`); `status_porcelain` was the old whole-tree
   guard probe, replaced by the staged-index probe. Removal is safe.

4. **Version + CHANGELOG — OK.** patch 0.17.0→0.17.1 is right: an internal
   refactor (dead-code removal + private rename) with no observable behavior,
   CLI, JSON, or on-disk change is a back-compat-only edit, i.e. patch per the
   project's SemVer rule. The `[0.17.1]` entry accurately describes both the
   removal and the rename and explicitly states "internal, no behavior change"
   and that the implementation + transaction guard/retry are unchanged.

5. **Coverage / api.rb gate — OK.** `lib/owl/commit_push/api.rb` was not modified
   and remains at 18/18 = 100% line coverage, satisfying the `**/api.rb` gate.
   `git_runner.rb` is at 20/26 (76.9%); the missed lines are other unexercised
   facade wrappers (`push`/`pull_rebase`/`head_sha`/rescue glue), not an `api.rb`
   file, so not gated — and the removal of the two 0-coverage dead methods is why
   the per-file fraction shifted from the TASK-0032-era 22/30. No gate impact.

# Resolution

Accepted. The change is exactly what the brief describes: two genuinely dead
public methods removed, one predicate renamed with an identical body and its one
caller updated, specs and the version/CHANGELOG aligned. Grep confirms zero
dangling references in code; behavior is provably unchanged; the full suite,
RuboCop, and the public-API coverage gate are all green. No changes required.

# Remediation

n/a — no defects found.

# Residual risks

- None of consequence. The old names persist only in historical CHANGELOG
  entries and task/docs prose, which is expected and intentionally not rewritten.
- `git_runner.rb` per-file line coverage (76.9%) reflects other long-standing
  unexercised facade wrappers, unrelated to this change and outside the gated
  `**/api.rb` set.
