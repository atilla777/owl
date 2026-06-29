---
status: approved
summary: Harden the owl-* skills — remove the last hardcoded Russian strings from owl-step-discussion (Language-Clause compliance), and add a CLI error codebook, a command-selection decision tree, and explicit variant-selection + heartbeat-cadence guidance to the owl-cli skill.
---

# Problem

The materialised `owl-*` skills carry residual rough edges that contradict
their own conventions or leave agents to rediscover CLI semantics by trial:

1. **Hardcoded Russian strings.** `skills/owl-step-discussion/SKILL.md`
   (the `owl recall` brief-memory block, lines ~99 and ~104) instructs the
   agent to print fixed Russian literals — `«Похожие архивные задачи»` and
   `«похожих архивных задач не найдено»`. This directly violates
   `_owl_conventions.md` §7 (Language Clause): every user-facing string MUST
   be emitted in `settings.language.communication`, with English fallback.
   The skill is meant to be language-agnostic; baking RU in breaks any
   consumer project whose communication language is not Russian.

2. **No CLI error codebook.** `skills/owl-cli/SKILL.md` tells agents to
   "surface the structured error rather than guessing recovery" but never
   enumerates the codes. Recovery for common structured errors
   (`lease_held`, `lease_lost`, `active_step_locked`, `step_not_running`,
   `composite_with_unready_children`, `step_not_ready`, `condition_unmet`,
   etc.) is scattered across the orchestrator prose, so each agent re-derives
   it. There is no single code → meaning → resolution → exit-code reference.

3. **No command-selection decision tree.** There is no quick "given this
   situation, call this command" map. Agents must read long skill prose to
   learn, e.g., that "what's next?" is `owl next` (never the first row of
   `owl task list`), or that a stuck `running` step needs `owl task adopt`.

4. **Underdocumented variants & heartbeat cadence.** Step variants are
   mentioned only in passing in `owl-cli`. Heartbeat is documented as a
   command but with **no cadence** — agents do not know *when* or *how often*
   to call `owl task heartbeat` relative to `claim_ttl_seconds`, so long
   execution steps risk silent lease loss (`lease_lost`).

This is a documentation/skills-content hardening task. It touches only
`skills/**` (consumer-materialised seed content) and supporting prose — no
`lib/**`, no `bin/owl` behaviour, no JSON response shapes, no schemas, no
artifact `required_sections`. It is the natural follow-on to TASK-0047
(owl-* skill contradictions) and TASK-0039 (sync agent-facing docs).

# Goal

Bring the `owl-*` skills into full self-consistency:

- `owl-step-discussion` contains **zero** hardcoded natural-language
  literals; the `owl recall` block emits its labels in
  `settings.language.communication` per §7, defaulting to English.
- `skills/owl-cli/SKILL.md` gains three new reference subsections — a CLI
  **error codebook**, a **command-selection decision tree**, and explicit
  **variant-selection + heartbeat-cadence** guidance — so an agent can pick
  the right command and recover from a structured error without reading the
  orchestrator prose. (Per the brief decision: all new reference content
  lives in `owl-cli`, the single canonical home for CLI semantics.)
- The change is propagated through the normal version-bump + materialisation
  path so consumer projects receive it.

# Scenarios

### Requirement: owl-step-discussion emits recall labels in the configured communication language

The system SHALL replace the hardcoded Russian recall-block literals in
`skills/owl-step-discussion/SKILL.md` with an instruction to emit those
labels in `settings.language.communication`, defaulting to English.

#### Scenario: recall block carries no hardcoded Cyrillic
- WHEN `grep -rn '[А-Яа-яЁё]' skills/owl-step-discussion/SKILL.md` is run after the change
- THEN it returns no matches
- AND the recall-block step still instructs the agent to show a "similar archived tasks" heading and a "no similar archived tasks found" line, but in the language resolved from `settings.language.communication`

#### Scenario: skill defers to the §7 Language Clause
- WHEN the recall-block instructions are read
- THEN they reference `_owl_conventions.md` §7 (Language Clause) as the source of the language rule
- AND they specify the English fallback when `settings.language.communication` is missing

### Requirement: owl-cli skill provides a structured-error codebook

The system SHALL add to `skills/owl-cli/SKILL.md` a codebook that maps each
common `bin/owl` structured error code to its meaning, the recommended
recovery action, and its CLI exit code.

#### Scenario: codebook covers the recurring error codes with real recovery
- WHEN an agent hits a structured error such as `lease_held`, `lease_lost`, `active_step_locked`, `step_not_running`, `composite_with_unready_children`, `step_not_ready`, or `condition_unmet`
- THEN the codebook lists that code with a one-line meaning and the concrete recovery command (e.g. `active_step_locked` → complete/reopen the running step or `owl step reset`; `needs_adopt`/stuck running → `owl task adopt`; `lease_held` → stop unless `--steal`)
- AND each entry states the resulting exit code where it is non-zero

#### Scenario: codes are verified against the implementation, not invented
- WHEN the codebook is authored
- THEN every listed code is confirmed to be emitted by the current `bin/owl` / `lib/owl` code or seeded skill prose
- AND no fictional or deprecated code is listed

### Requirement: owl-cli skill provides a command-selection decision tree

The system SHALL add to `skills/owl-cli/SKILL.md` a decision tree mapping
common agent situations to the correct `bin/owl` command.

#### Scenario: "what's next?" routes to owl next
- WHEN an agent consults the decision tree for "what should I work on next?"
- THEN the tree directs it to `owl next --json`
- AND it explicitly warns against picking the first row of `owl task list` as a work-readiness ranking

#### Scenario: tree covers claim/adopt/heartbeat/reset branches
- WHEN an agent consults the tree for taking a lease, recovering a crashed session's stuck step, extending a lease, or clearing a reviewer-left running step
- THEN the tree routes them to `owl task claim`/`claim --next`, `owl task adopt`, `owl task heartbeat`, and `owl step reset` respectively

### Requirement: owl-cli skill documents variant selection and a concrete heartbeat cadence

The system SHALL document in `skills/owl-cli/SKILL.md` how step variants are
chosen and SHALL give a concrete recommended heartbeat cadence relative to
the claim TTL.

#### Scenario: variant selection is documented end-to-end
- WHEN an agent reads the variants guidance
- THEN it explains that a step declaring `variants:` resolves a `default_variant`, that a non-default is chosen with `--variant NAME` on `owl step start` (or `--variant STEP=NAME` on `owl task create`), and that the chosen `context_file` + overlay are then loaded automatically

#### Scenario: heartbeat cadence is concrete and normative
- WHEN an agent reads the heartbeat guidance
- THEN it states a concrete cadence: the agent SHOULD send `owl task heartbeat` at roughly 50% of `settings.concurrency.claim_ttl_seconds`, and MUST heartbeat before dispatching any execution step that may outlast the remaining TTL
- AND it states that a `lease_lost` (exit 2) response means another session took the task and the agent MUST stop driving it and re-resolve via `owl next`

### Requirement: the change is versioned and materialised for consumers

The system SHALL bump `Owl::VERSION` and add a `CHANGELOG.md` entry in the
same commit, and SHALL refresh this repo's materialised skills.

#### Scenario: version bump accompanies the skill edit
- WHEN the skills are edited under `skills/**`
- THEN `Owl::VERSION` is bumped (patch — back-compat additive docs/skill content) and a matching `CHANGELOG.md` entry is added in the same commit
- AND `bin/owl upgrade` (or the merge_docs/materialise path) refreshes `.claude/skills/owl-*` so the source and materialised copies agree

# Edge cases

- **Materialised vs source copies.** The canonical edit target is the
  `skills/owl-*` source tree; `.claude/skills/owl-*` are generated. The fix
  is incomplete until both agree (re-materialise via `bin/owl upgrade`).
  The grep-for-Cyrillic check MUST pass against the source tree.
- **Language fallback.** When `settings.language.communication` is unset, the
  recall labels fall back to English with the one-line note allowed by §7 —
  not to Russian.
- **Codebook drift risk.** The codebook documents error codes owned by the
  code; if a future code is renamed, the codebook can drift. Mitigate by
  cross-checking each listed code against the current implementation when
  authoring, and keep the list to recurring, agent-actionable codes rather
  than an exhaustive dump.
- **No behavioural change.** This task MUST NOT alter any `bin/owl` behaviour,
  exit code, JSON shape, schema, or artifact `required_sections`; it only
  documents existing behaviour. Any temptation to "fix" a code while
  documenting it is out of scope and belongs in its own task.
- **owl recall stays advisory.** The recall-block edit MUST preserve the
  existing contract that a non-empty / empty / failed recall never blocks or
  gates the brief step.

# Acceptance criteria

- `grep -rn '[А-Яа-яЁё]' skills/owl-step-discussion/SKILL.md` returns no
  matches; the recall block instead instructs emission in
  `settings.language.communication` (English fallback) and cites §7.
- `skills/owl-cli/SKILL.md` contains a new **error codebook** subsection
  mapping each recurring structured error code → meaning → recovery command →
  exit code, with every code verified against the current implementation.
- `skills/owl-cli/SKILL.md` contains a new **command-selection decision tree**
  that routes "what's next?" to `owl next` (with the explicit
  do-not-use-`owl task list`-order warning) and covers the
  claim/adopt/heartbeat/reset branches.
- `skills/owl-cli/SKILL.md` documents variant selection end-to-end and a
  concrete heartbeat cadence (SHOULD ~50% of `claim_ttl_seconds`; MUST before
  a long execution step) plus the `lease_lost` → stop-and-re-resolve rule.
- `Owl::VERSION` is bumped (patch) and `CHANGELOG.md` has a matching entry in
  the same commit.
- The materialised `.claude/skills/owl-*` copies are refreshed so source and
  materialised content agree.
- No `lib/**`, `bin/owl`, schema, JSON-shape, or artifact-`required_sections`
  change is introduced; RuboCop and RSpec remain green.
