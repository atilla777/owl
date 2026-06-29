# Goal

Harden the `owl-*` skills (source tree `skills/**`, then re-materialise into
`.claude/skills/`) so they no longer contradict their own conventions or leave
agents to rediscover CLI semantics: (1) remove the last hardcoded Russian
literals from `owl-step-discussion` (§7 Language-Clause compliance), and add to
`owl-cli` (2) a verified structured-error codebook, (3) a command-selection
decision tree, and (4) explicit variant-selection + heartbeat-cadence guidance.
Bump `Owl::VERSION` 1.3.0 → 1.3.1 (patch, additive docs/skill content) with a
matching `CHANGELOG.md` entry, and re-materialise. No `lib/**`, `bin/owl`,
schema, JSON-shape, or artifact-`required_sections` change.

# Checklist

- [ ] `skills/owl-step-discussion/SKILL.md` — in the "Brief-step cross-task
  memory (`owl recall`)" section (steps 2–3), replace the hardcoded Russian
  literals `«Похожие архивные задачи»` (line ~99) and `«похожих архивных задач
  не найдено»` (line ~104) with language-neutral instructions: show a
  "similar archived tasks" heading and, when empty, a "no similar archived
  tasks found" line, **emitted in `settings.language.communication`** with an
  English fallback, citing `_owl_conventions.md` §7 (Language Clause). Preserve
  the existing advisory contract (recall never blocks/gates the brief).
- [ ] `skills/owl-cli/SKILL.md` — add a new **"Structured-error codebook"**
  subsection (after "Response Shape Notes"): a table mapping each recurring,
  agent-actionable error `code` → one-line meaning → concrete recovery command
  → `error_class` and exit code. Use only codes verified in this plan's
  research. Seed rows (all verified against `lib/owl`):
  - `lease_held` (recoverable, exit 2) → another live session owns the task;
    stop unless the user asks to `owl task claim --steal`.
  - `lease_lost` (recoverable, exit 2) → lease gone/taken; stop driving and
    re-resolve via `owl next`; `owl task adopt`/`claim` to take over.
  - `active_step_locked` (recoverable, exit 2) → this task already has a
    running step; complete/reopen it, or `owl step reset TASK STEP` for a
    reviewer-left `running` step (e.g. after a `changes_required` review).
  - `step_not_running` (validation, exit 1) → `complete`/`reopen`/`reset`
    target is not `running` (often a safe no-op confirming the executor
    already completed it).
  - `step_not_ready` (validation, exit 1) → step's `requires:` are unmet; pick
    the step `owl next` returns instead.
  - `step_already_done` (validation, exit 1) → step is terminal; nothing to do.
  - `no_available_task` / `no_current_task` (validation, exit 1) → nothing
    runnable / no current pointer; stop and report, don't guess.
  - `workflow_incomplete` (validation, exit 1) → `owl archive` rejected: steps
    not done/skipped (this is what a composite parent with unready children
    surfaces — NOT a `composite_with_unready_children` code, which does not
    exist; children-wait is the **status** `blocked_by_children`).
  - `publish_required` (validation, exit 1) → archive blocked because the
    `publish`/`merge_docs` step must be `done` first.
  - `confirmation_required` / `missing_reason` (validation, exit 1) → a
    destructive/optional op needs `--force` / `--reason`.
  - `drift_block` (recoverable, exit 2) → workspace drift under a `block`
    policy; reconcile (`owl doctor`) before proceeding.
  - State the exit-code legend once: `error_class` → exit (`validation`=1,
    `recoverable`=2, `fatal`=3, `step_context_frontmatter`=4), sourced from
    `lib/owl/cli/internal/json_printer.rb`.
- [ ] `skills/owl-cli/SKILL.md` — add a new **"Command-selection decision
  tree"** subsection: situation → command. Must include: "what's next?" →
  `owl next --json` with an explicit warning **not** to use the first row of
  `owl task list` as a work-readiness ranking; "take the task" →
  `owl task claim TASK` / `owl task claim --next`; "prior session crashed,
  step stuck `running`" → `owl task adopt TASK`; "lease about to expire mid-
  step" → `owl task heartbeat`; "reviewer left `review_code` running
  (changes_required)" → `owl step reset TASK review_code`; "optional step,
  obvious path" → `owl step skip`; "condition-unmet `when:` step" → auto-skip;
  "validate before complete" → `owl artifact validate` (inspect `ok`).
- [ ] `skills/owl-cli/SKILL.md` — extend the existing variants/heartbeat notes
  into an explicit **"Variant selection & heartbeat cadence"** subsection:
  - Variants end-to-end: a step declaring `variants:` resolves its
    `default_variant`; choose a non-default with `--variant NAME` on
    `owl step start` (or `--variant STEP=NAME` on `owl task create`); the
    chosen `context_file` + overlay `<step>/<variant>.md` then load
    automatically.
  - Heartbeat cadence (concrete, normative): the agent **SHOULD** send
    `owl task heartbeat TASK --token T` at roughly **50% of
    `settings.concurrency.claim_ttl_seconds`** (default 600s → ~300s), and
    **MUST** heartbeat before dispatching any execution step that may outlast
    the remaining TTL. A `lease_lost` (exit 2) response means another session
    took the task → stop driving it and re-resolve via `owl next`.
- [ ] `lib/owl/version.rb` — bump `VERSION` `'1.3.0'` → `'1.3.1'`.
- [ ] `CHANGELOG.md` — add a `1.3.1` entry summarising the skill hardening
  (RU-string removal + owl-cli codebook/decision-tree/variant+heartbeat docs).
- [ ] Re-materialise: run `bin/owl upgrade` (or `bin/owl init --force`) so
  `.claude/skills/owl-step-discussion` and `.claude/skills/owl-cli` match the
  edited source; confirm source and materialised copies agree.

# Smoke test

- `grep -rn '[А-Яа-яЁё]' skills/owl-step-discussion/SKILL.md` → no matches.
- `grep -rn '[А-Яа-яЁё]' .claude/skills/owl-step-discussion/SKILL.md` → no
  matches (materialised copy refreshed).
- `grep -c 'codebook\|decision tree\|heartbeat' skills/owl-cli/SKILL.md` → the
  three new subsections are present.
- `grep -n 'composite_with_unready_children' skills/owl-cli/SKILL.md` → absent
  (no phantom code documented).
- `ruby -r./lib/owl/version -e 'puts Owl::VERSION'` → `1.3.1`; `CHANGELOG.md`
  has a matching `1.3.1` heading.
- `bundle exec rspec` and `bundle exec rubocop` both green (no behavioural
  code touched, but run the full gate since `lib/owl/version.rb` changed).

# Scope

Documentation/skills-content hardening only. Edits are confined to:
`skills/owl-step-discussion/SKILL.md`, `skills/owl-cli/SKILL.md`,
`lib/owl/version.rb`, `CHANGELOG.md`, and the regenerated `.claude/skills/owl-*`
materialised copies. All four brief deliverables land here.

# Constraints

- The canonical edit target is the `skills/owl-*` **source** tree;
  `.claude/skills/owl-*` are generated — never hand-edit only the generated
  copy. The fix is incomplete until both agree.
- Every error code listed in the codebook MUST be one emitted by the current
  `lib/owl`/`bin/owl` (verified in research) — no invented or deprecated codes.
  Do **not** document `composite_with_unready_children` (phantom).
- No behavioural change: no edits to `bin/owl`, `lib/owl/**` except the version
  constant, no schema/JSON-shape/`required_sections` change. The codebook
  *documents* existing behaviour; it must not motivate a code change here.
- Preserve `owl recall`'s advisory contract in the discussion skill.
- Per Constitution §7.1: the `skills/**` change MUST ship with a `Owl::VERSION`
  bump + `CHANGELOG.md` entry in the same commit.

# Files to inspect

- `skills/owl-step-discussion/SKILL.md` (recall block, lines ~96–106).
- `skills/owl-cli/SKILL.md` (Response Shape Notes ~109; variants ~114; heartbeat
  ~97; Stop Conditions ~171 — insertion points for the new subsections).
- `skills/_owl_conventions.md` §7 (Language Clause — cite, don't duplicate).
- `lib/owl/cli/internal/json_printer.rb` (`EXIT_CODES` legend — already read).
- `lib/owl/tasks/internal/claim_service.rb` (`lease_held`/`lease_lost`).
- `lib/owl/tasks/internal/archive/completion_gate.rb` (`workflow_incomplete`,
  `publish_required`).
- `lib/owl/version.rb`, `CHANGELOG.md`.

# Tests and verification

- No new RSpec needed (no `lib/owl/**/api.rb` logic added). Run the full gate
  anyway because `lib/owl/version.rb` changed: `bundle exec rspec` green,
  `bundle exec rubocop` green.
- Manual smoke checks listed under "Smoke test" above.
- `merge_docs` will be a no-op (design was skipped; no `docs/` publish target),
  which is expected for a skills-only change.

# Out of scope

- Any change to `bin/owl` behaviour, exit codes, JSON response shapes, schemas,
  or artifact `required_sections`.
- Rewriting orchestrator prose at large; only fix the phantom-code reference if
  it appears inside the files edited here (owl-cli). Broader prose sync belongs
  to a separate task.
- An exhaustive dump of all ~180 error codes — the codebook covers recurring,
  agent-actionable codes only.
- SQLite/loops/sub-workflow and other deferred backlog items.
