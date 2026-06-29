---
status: resolved
summary: owl-* skills hardening reviewed — RU literals removed from owl-step-discussion (§7-compliant), owl-cli gained a verified error codebook + command-selection decision tree + variant/heartbeat guidance, phantom composite_with_unready_children corrected, version 1.3.1 + CHANGELOG, materialised copies refreshed. RuboCop 0 offenses, RSpec 2090/0 failures. No defects.
verdict: accepted
ready: true
---

# Summary

Self-review of the TASK-0052 docs/skills-content hardening change. All seven
acceptance criteria from the plan are satisfied and the objective gate is
green. No defects, no scope leakage. Verdict: APPROVED / accepted.

# Findings

1. **owl-step-discussion RU literals removed — PASS.** Both hardcoded Russian
   literals (`«Похожие архивные задачи»`, `«похожих архивных задач не найдено»`)
   are gone, replaced with language-neutral instructions to emit a "similar
   archived tasks" heading and a "no similar archived tasks found" line in
   `settings.language.communication` (English fallback), citing
   `_owl_conventions.md` §7. The advisory contract (step 4: recall never
   blocks/gates the brief) is preserved verbatim. `grep -rn '[А-Яа-яЁё]'` over
   source and materialised copies returns no matches.

2. **owl-cli codebook + decision tree + variant/heartbeat — PASS.**
   - Error codebook present with the exit-code legend (validation=1,
     recoverable=2, fatal=3, step_context_frontmatter=4) — verified an exact
     match against `EXIT_CODES` in `lib/owl/cli/internal/json_printer.rb`.
   - All 13 documented codes are REAL, confirmed emitted by `lib/owl`:
     lease_held, lease_lost, active_step_locked, step_not_running,
     step_not_ready, step_already_done, no_available_task, no_current_task,
     workflow_incomplete, publish_required, confirmation_required,
     missing_reason, drift_block. Spot-checked error_class→exit:
     `drift_block`→recoverable/2 and `confirmation_required`→validation/1 both
     match source.
   - Decision tree routes "what's next?" → `owl next --json` with the explicit
     do-not-rank-by-`owl task list`-order warning; covers
     claim/adopt/heartbeat/reset/skip/when-auto-skip/validate.
   - Variant-selection end-to-end (`--variant NAME` / `--variant STEP=NAME`,
     auto-loaded context_file + overlay) and normative heartbeat cadence
     (SHOULD ~50% of claim_ttl_seconds; MUST before a long execution step;
     lease_lost exit 2 → stop + re-resolve) both present.
   - NO phantom `composite_with_unready_children` remains (grep returns
     nothing); the three former references corrected to `workflow_incomplete` +
     `blocked_by_children` status.

3. **Version + CHANGELOG — PASS.** `Owl::VERSION` 1.3.0 → 1.3.1 (patch correct
   for additive docs/skill content); matching `[1.3.1] - 2026-06-29` CHANGELOG
   entry in existing format.

4. **Materialised copies — PASS.** `diff` of source vs `.claude/skills/*` for
   both owl-cli and owl-step-discussion → IDENTICAL.

5. **Scope discipline — PASS.** `git diff --stat -- lib/` shows only
   `version.rb`. Only spec change is `brief_surface_spec.rb` (it asserted the
   removed RU literals; now asserts the language-neutral contract + no-Cyrillic
   guard + §7 deference). `.owl/config.yaml` and `Gemfile.lock` version bumps
   are expected re-materialisation side-effects, not behavioural code.

# Resolution

No findings require remediation. The change is accepted as implemented.

# Remediation

None required.

# Residual risks

- Codebook drift: documented codes are owned by `lib/owl`; a future rename
  could desync the codebook. Each code was cross-checked against current
  source at review time. Low risk, accepted.
- (Informational) Active-step-lock wart carried from the implement report —
  `owl step reset` cannot clear a stale lock for a non-`running` step. Out of
  scope for TASK-0052; candidate for a follow-up task.
