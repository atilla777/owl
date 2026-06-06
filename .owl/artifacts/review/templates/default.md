---
status: open
summary: TODO — one-line headline of the review outcome.
verdict: changes_required
ready: false
---

# Review

## Summary

TODO — one paragraph: scope of changes reviewed, overall verdict.

Set front matter `verdict` to one of `accepted` / `accepted_with_followups`
/ `changes_required`, and `ready` to `true` only when the change is fit to
ship.

## Findings

- [ ] TODO — concrete finding (file:line, what's wrong, severity).

If no findings, write a single line: `- None.`

## Resolution

TODO — for each finding, how it was addressed (fixed in this branch /
deferred with reason / accepted with rationale). Set `status: resolved`
in front matter once all findings have a resolution.

## Remediation

TODO — concrete follow-up actions still owed (who/what), or `None` if the
change is clean. Pairs with `verdict: accepted_with_followups`.

## Residual risks

TODO — known risks that remain after this change (areas not covered,
assumptions, things to watch in prod). `None` if none.
