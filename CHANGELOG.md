# Changelog

All notable changes to `owl-cli` are documented here. The format is loosely
based on [Keep a Changelog](https://keepachangelog.com/); this project uses
semantic versioning.

## [0.11.0] - 2026-06-24

### Added
- **`owl task child create … --brief-body -` (TASK-0024).** Decompose can now
  hand a child its brief markdown over stdin (or an inline `--brief-body BODY`),
  matching the `--body -` convention of `workflow context set` /
  `artifact-type template set`. This removes the need to write scratch brief
  files under `tasks/<PARENT>/.briefs/`. `--brief` and `--brief-body` are
  mutually exclusive (clear error if both are given). The supplied body now
  passes normal brief artifact validation before the brief step is marked
  `done`; an invalid body returns a clear `brief_invalid` error instead of
  silently creating a "done" brief. Existing `--brief PATH` and no-brief
  behaviour are unchanged.

### Changed
- **Decompose context drops the `.briefs/` scratch flow and requires
  non-overlapping child scopes (TASK-0024).** `composite_feature/decompose`
  now instructs the agent to pipe each child brief via `--brief-body -`
  (heredoc/stdin) and to verify children have non-overlapping file scopes at
  decompose time (a short checklist), rather than leaving overlap for review to
  catch.
- **Skill/overlay docs hardened (TASK-0024).** `_owl_conventions` /
  `owl-step-execution` now state that dependent owl commands (a mutator followed
  by a reader, especially `step start` → `step show`) must run sequentially,
  never in parallel, to avoid a stale-read race. `owl-orchestrator` and the
  `review_code` overlay now document that a `changes_required` verdict leaves
  the review step `running` and the operator must
  `owl step reset <TASK-ID> review_code` before re-running.

## [0.10.0] - 2026-06-24

### Added
- **Group commands now print their subcommand list (TASK-0023).** `owl step`
  and `owl step --help` (and the same for `task`, `workflow`, `artifact`,
  `artifact-type`, `config`, `git`, `plan`, `spec`) previously failed with
  `unknown_command`; they now emit the group's available subcommands and exit 0.
  A concrete-but-unknown verb (`owl step bogus`) still returns `unknown_command`
  with its prior exit code. `--json` yields a machine-readable
  `{ ok, command, subcommands }` list; plain mode prints a human-readable usage
  block. Bare-arg groups (`archive`, `recall`, `commit-push`) keep their
  positional behaviour.
- **`owl task claim --steal` hints at adopt for a wedged step (TASK-0023).**
  When a steal displaces a session that left a step `running`, the success
  response gains additive `running_step` and `hint` fields pointing at
  `owl task adopt TASK-ID` (which resets the stuck step); the hint is also echoed
  to stderr. Claim success, exit code, and existing response fields are
  unchanged.

### Fixed
- **`owl task child create … --brief …` no longer prints a stale step status
  (TASK-0023).** The JSON payload now re-reads the task after the brief prefill,
  so it reflects `brief: done` instead of the pre-prefill `brief: pending`.

## [0.9.0] - 2026-06-24

### Changed
- **`require_when_then` scenario validation now accepts WHEN/THEN
  case-insensitively (TASK-0022).** The `WhenThenChecker` clause regexes
  previously matched only UPPERCASE `WHEN`/`THEN`, so a `#### Scenario:` block
  written with Title-case (`- When …`) or lower-case (`- when …`) bullets was
  rejected even though it was well-formed Gherkin prose. Both clause regexes now
  carry the `i` flag, accepting any case while preserving the existing
  leading-prefix tolerance (`>`, `*`, `-`, whitespace, bold markers) and full
  UPPERCASE back-compat. This loosens a validation contract, hence the MINOR
  bump.
- **Missing-clause error message is now actionable.** The
  `scenario_missing_clause` violation `description` now spells out the expected
  format — `expected a line like '- WHEN …' (case-insensitive) inside the
  '#### Scenario:' block` — instead of the bare `is missing a WHEN clause.`. The
  violation `type` and `missing` keyword fields are unchanged, so downstream
  consumers keying on those are unaffected.

## [0.8.1] - 2026-06-24

### Fixed
- **Concurrent roster mutations no longer lose updates (TASK-0021).** Every
  write of `tasks/index.yaml` (create, archive, delete, abandon, set-priority,
  and `owl task index rebuild`) now runs its full filesystem scan + atomic
  write under a repo-scoped `Owl::Locks` lock named `index`. Previously the
  index was rebuilt by a full scan and written atomically (write+rename), which
  prevented a *corrupt* file but not a *lost update*: two sessions mutating the
  roster at the same time would both scan, both write, and the last `rename`
  would win — silently dropping the other session's change. This is exactly the
  parallel-orchestrator scenario Owl encourages. A new
  `Owl::Tasks::Internal::IndexWriter` centralizes the locked scan+write and all
  roster writers route through it; the lock is a leaf (acquired immediately
  before the scan, released in an `ensure`) so a normal single-session chain
  (create → … → archive) never self-deadlocks, and it carries the same TTL /
  auto-reclaim semantics as the other Owl locks so a crashed session cannot
  wedge the roster permanently. Because the lock primitive is non-blocking,
  `IndexWriter` retries acquisition with a short backoff up to a bounded
  deadline to actually serialize contending writers instead of failing one.

## [0.8.0] - 2026-06-24

### Added
- **Fresh `owl init`/`owl upgrade` now ships all five workflows
  (TASK-0020).** `hotfix`, `refactor`, and `quick` were valid only in this
  repo's dogfood `.owl/workflows/` copy and never reached the gem
  distribution: `owl-cli.gemspec` packs the repo-root `workflows/` tree (which
  held only `feature` + `composite_feature`) and the default registry in
  `Owl::Workflows::Internal::DefaultTemplate.render` registered just those two.
  The three workflow seed directories (`workflow.yaml` + every `*.context.md`)
  are now promoted into repo-root `workflows/hotfix/`, `workflows/refactor/`,
  and `workflows/quick/`, and the default registry registers all five as
  `managed: true` (version `1.0`) with `source:` paths that resolve against the
  shipped seed tree. This resolves the open question on `quick`: it ships as a
  managed seed, not a registered-but-undelivered example.
- **Requirement/Scenario grammar is now self-contained for consumer
  projects.** The `brief` artifact's `required_patterns` description and the
  brief context/template files previously pointed at
  `docs/agents/31_Owl_Requirement_Scenario_grammar.md`, which is not seeded into
  consumer projects (a dead link, observed in the `re` project). A compact
  "Requirement/Scenario grammar" section (RFC 2119 `### Requirement:` headings +
  `#### Scenario:` blocks with UPPERCASE `- WHEN` / `- THEN` lines) is now
  embedded directly in every seeded brief context file across all five
  workflows, and the brief `artifact.yaml` / `templates/default.md` references
  point at that inline section instead of the unshipped doc path.
  `docs/agents/31_…` remains the extended canon inside the Owl repo.

## [0.7.2] - 2026-06-23

### Fixed
- **Composite `children_complete` gate no longer wedges when a child
  self-archives (TASK-0019).** A composite parent's gated `archive`/`commit_push`
  steps open only when `owl task aggregate-status PARENT` ∈ {ready, done}, but the
  aggregate was computed solely from the active `tasks/index.yaml`. Once the last
  child ran `owl archive CHILD` it left the index, `ChildrenLister` saw an empty
  set, and `aggregate_state` returned `'open'` forever — stranding the parent.
  `ChildrenLister` now also folds in archived children, discovered by `parent_id`
  through the public `Owl::Archive::Api.list` boundary (dedup by task id,
  preferring the archived/terminal entry), so a fully-archived child yields state
  `archived` → aggregate `done` → the gate opens. A parent that never had any
  children still aggregates `open` (no false open).

### Added
- **`owl archive list` now exposes `parent_id` per archived entry.**
  `Owl::Archive::Api.list` reads the archived `task.yaml` (already read for
  `title`) and surfaces its `parent_id` as an additive field — closing the gap
  where the parent→child link survived in the archived payload but was never
  visible through the archive read surface.

## [0.7.1] - 2026-06-23

### Changed
- **Harden the objective verification gate (TASK-0017).** Added direct specs
  for the two previously-unpatched layers of the gate: the real subprocess
  runner `Owl::Verification::Internal::CommandRunner` is now exercised with
  genuine short subprocesses (exit-code propagation, stdout/stderr capture,
  `timeout` → `TERM` of the whole process group with a verified-dead child, and
  spawn failure on a missing `chdir`), and the `owl verify TASK-ID` CLI command
  is covered across all of its branches (`invalid_arguments`, fail-open
  `gate_active:false` + warning, active gate `passed`/`failed`, and structured
  engine-error propagation). No behaviour change.

### Removed
- **Dead `Owl::Verification::Internal::Gate.resolve_step_id`.** The method had
  no callers anywhere in `lib/` or `spec/` (the live copy used by the publish
  gate lives in `Owl::Publish::Internal::StepGate`); the verification gate
  resolves `verify: true` steps directly. Removing it changes no observable
  behaviour. Public `Owl::Verification::Api` signatures are untouched.

## [0.7.0] - 2026-06-23

### Added
- **`owl commit-push TASK-ID --message M` — transactional `commit_push`.** New
  CLI command + `Owl::CommitPush::Api.commit_push` facade that runs the whole
  terminal step as one operation: `git add -A` → flip `commit_push: done` in
  `task.yaml` → re-`git add -A` (so the flip rides the same commit) → acquire
  the repo-scoped `git` push lock → `git commit` → `git pull --rebase` →
  `git push` → release the lock. This removes the old "complete-before-commit"
  ordering hack and its separate "sync … step state to done" commit. Failure
  semantics: any failure **before** `git commit` rolls the step back to
  `running` and creates no commit; a successful commit whose `pull --rebase`/
  `push` fails keeps the local commit and reports `push_retryable`
  (`rebase_conflict` on a rebase conflict) so a re-run is idempotent — it takes
  the retry branch (clean tree + step `done` + unpushed commit) and only
  re-attempts pull + push, never a second commit. `nothing_to_commit` is
  returned (step left `running`) when staging produces no changes. Git runs
  through an injectable `Owl::CommitPush::Internal::GitRunner` (Open3, like the
  upgrade `ShellRunner`) so the flow is unit-tested without real git or the
  network; the push lock reuses `name: 'git'` (same as `owl git lock`). Emits
  `{ ok: true, task_id, commit_sha, pushed }` or `{ ok: false, error: { code, … } }`.
- **`Owl::Steps::Api.status` / `Owl::Steps::Api.mark_running`.** Root-scoped
  helpers backing the `commit_push` transaction: read a single step's status,
  and force a step back to `running` (rollback half of the transaction).

### Changed
- **`commit_push` skill / context / overlay now call `owl commit-push`.** The
  `feature` and `composite_feature` `commit_push.context.md`, the
  `.owl/overlays/commit_push.md` Sequence section, and the `owl-step-execution`
  skill replace the manual 7-action prose (stage → complete → re-stage → lock →
  commit → pull → push → unlock) with a single `owl commit-push TASK-ID
  --message "Owl: …"` call; preconditions (`git status` review, push to `main`,
  one commit) and stop-conditions are preserved as pre-call checks.

## [0.6.0] - 2026-06-23

### Added
- **`owl recall <query>` — cross-task memory over the archive.** New
  read-only CLI command that lexically (tf-idf, length-normalized,
  pure Ruby, no network or new gems) ranks similar ARCHIVED tasks by
  their `title` + brief `Problem`/`Goal` sections and emits
  `{ ok: true, matches: [{ task_id, title, score, snippet }] }` sorted by
  score descending then `task_id` ascending. `--limit N` truncates
  (default 10); a trivial query (empty / stopword-only), an empty archive,
  or no matches all yield `{ ok: true, matches: [] }` at exit 0 — it never
  crashes. The corpus is built only through `Owl::Archive::Api`
  (`list`/`read`), never a direct `File.read`. New `Owl::Recall::Api`
  facade with internal `Tokenizer` (Unicode/Cyrillic-aware), `CorpusBuilder`,
  and `Scorer`. The `owl-step-discussion` skill surfaces the result on the
  `brief` step as a «Похожие архивные задачи» block; an empty/failed recall
  prints one line and never blocks the step.

## [0.5.0] - 2026-06-23

### Added
- **`owl publish` now flips the design to `shipped`.** After a successful
  non-dry-run publish, a publishable artifact whose type declares a `status`
  enum including `shipped` (in practice `design`) is flipped from `approved`
  to `shipped` in the canonical source (`tasks/<ID>/design.md`) BEFORE the
  copy, so the published `docs/<ID>/design.md` carries `shipped` and the two
  stay consistent. Idempotent (already-`shipped` is a no-op); no-op on
  dry-run, missing source, or no front-matter. Implemented by
  `Owl::Publish::Internal::StatusFlipper`. This fixes the long-standing
  documented-but-missing behavior.
- **`owl publish` maintains a generated `docs/README.md` index.** After a
  non-dry-run publish, `Owl::Publish::Internal::DocsIndex` scans every
  `docs/TASK-*/` directory and (re)writes a deterministic, idempotent index
  of published task docs (links + front-matter `summary` when present, sorted
  by TASK-ID, no timestamps). dry-run does not write. The generated index is
  reproducible from `docs/` and is therefore not backed up.
- `owl publish --json` result gains two additive keys: `design_status`
  (`flipped_to_shipped` | `already_shipped` | `not_applicable`) and `index`
  (`{updated, path: "docs/README.md"}`). Existing keys (`results[].action`,
  `step_status`, `dry_run`, error codes) are unchanged.

### Changed
- Rewrote the `merge_docs` step context (source + materialized
  `feature`/`hotfix`/`refactor` variants) and trimmed README overselling to
  describe what publish actually does — publish artifacts per `publishes`
  rules, flip the design to `shipped`, refresh the `docs/README.md` index,
  and apply the optional `spec_delta` — without claiming "merge published
  docs" / "knowledge base" semantics.

## [0.4.0] - 2026-06-23

### Added
- **Optional per-workflow plan-approval gate (`gate: plan_approved`).** A
  workflow step (typically `implement`) can now declare `gate: plan_approved`
  to require explicit approval of the task's plan before it becomes ready.
  While unapproved, the step is held out of `owl task ready-steps` and surfaced
  under a new `awaiting_plan_approval` array; `owl next` returns the new
  `action.kind: await_plan_approval`. The gate works for any task kind and is
  independent of the composite `children_complete` gate. **Off in every seeded
  workflow** (`feature`/`composite_feature`/`hotfix`/`refactor`) — default
  autonomy is unchanged and `owl upgrade` never enables it.
- **`owl plan approve TASK-ID [--token TOKEN]`** — records persistent,
  task-level plan approval (top-level `plan_approval { approved, plan_sha,
  approved_at }` in `task.yaml`). Lease-aware (rejected with `lease_held` when a
  different live session holds the claim), idempotent for an already-approved
  plan, and refused with `plan_not_completed` until the `plan` step is done.
  Approval is bound to the plan artifact's `content_sha`.
- **`owl plan status TASK-ID`** — read-only `{approved, plan_sha, gate_open}`.
- `Owl::Tasks::Api.approve_plan` / `.plan_status` and
  `Owl::Tasks::Internal::PlanApproval` (with a `gate_open?` helper).
- `owl step reopen TASK-ID plan` now clears any recorded plan approval (directly
  or via `--cascade`), so a stale plan cannot pass the gate.
- `WorkflowValidator` rejects `gate: plan_approved` on a workflow with no `plan`
  step (`gate_requires_plan`); the `gate` step property is now enumerated in
  `schemas/workflow.json` (`children_complete` | `plan_approved`).
- Documented default autonomy as a deliberate trade-off and the opt-in gate in
  `skills/_owl_conventions.md` (§9) and `skills/owl-orchestrator/SKILL.md`.

### Changed
- `owl task ready-steps --json` / `Owl::Workflows::Api.ready_steps` now include
  an additive `awaiting_plan_approval: [step_id, …]` key alongside `ready` and
  `blocked_by_children`.

## [0.3.0] - 2026-06-23

### Added
- **Objective verification gate (`verify: true` step-marker + `owl verify`).**
  A step can now opt into an objective verification gate with a boolean
  `verify: true` marker (mirroring the `publishes: true` precedent). At
  `owl step complete`, Owl itself runs the project's
  `settings.verification.command` as a subprocess, derives the status from its
  exit code, and **authors** the `verification` artifact — the status can no
  longer be faked by an agent self-report. Completion is refused (structured
  `verification_failed`, non-zero exit, step stays `running`) unless the
  objective status is `passed`; the result is fresh by construction because the
  run happens at completion time. Fix a failure with
  `owl step reopen TASK-ID implement --cascade`.
- New `Owl::Verification` domain (`Api.run` / `Api.gate` /
  `Api.configured_command`, with injectable `Internal::CommandRunner`,
  `Internal::Engine`, `Internal::Gate`, `Internal::ReportWriter`).
- **`owl verify TASK-ID [--json]`** — run the verification command for a task
  without completing a step (a convenience pre-check); reports
  `{ok, status, exit_code, command, gate_active}`. `gate_active: false` with a
  warning when no command is configured.
- `settings.verification.command` (string|null) and
  `settings.verification.timeout_seconds` (positive integer, default 1800) are
  now recognized and validated in `.owl/config.yaml`
  (`invalid_settings_verification_shape` /
  `invalid_settings_verification_command` /
  `invalid_settings_verification_timeout`). A commented example ships in the
  default config template. New workflow step field `verify` (boolean) in
  `schemas/workflow.json`.

### Changed
- **Verification ownership moved from `implement` to `review_code`.** In the
  seeded `feature` workflow `creates: [verification]` now lives on `review_code`
  (alongside `creates: [review]`), which carries `verify: true`; `implement`
  becomes a build-only step that creates no artifact. Step context files updated
  accordingly. Only new tasks pick up the new graph (in-flight `task.yaml` files
  are untouched).

### Compatibility
- **Opt-in and fail-open.** With no `settings.verification.command` configured,
  the gate is inactive: `owl step complete` proceeds and prints a
  `verification_gate_inactive` warning. A `partial` status does not block
  (warning only). Existing consumers that do not configure a command keep their
  current behaviour across `owl upgrade`.

## [0.2.0] - 2026-06-23

### Added
- **`owl next [TASK-ID] --json` — read-only next-action advisor.** A new
  top-level command that encapsulates the orchestrator's whole "what do I do
  next?" decision in code instead of skill prose. It runs the canonical
  selection ladder (explicit `TASK-ID` › current pointer › auto-select the top
  `owl task available` candidate) and classifies the outcome into a single
  discriminated `action.kind ∈ {dispatch_step, handoff_composite, stop_blocked,
  done, no_available_task}`. All outcomes exit 0 (a terminal outcome is a valid
  result, not an error); the raw `no_current_task` error no longer leaks — it
  maps to `no_available_task`. `task_resolution` reports `source ∈ {explicit,
  current_pointer, auto_select, none}` with a `reason` and a `needs_adopt` flag
  (set when the chosen task has an expired lease over a stuck `running` step).
  The command is idempotent and never mutates state (no claim, no step start) —
  claim/adopt remain explicit orchestrator follow-ups.
- New `Owl::Orchestration` domain (`Api.next_action`, read-only
  `Internal::NextActionResolver` + shared `Internal::TaskResolver`) composing
  the existing Tasks/Workflows/Steps APIs.

### Changed
- **Skill prose deduplicated.** `owl-orchestrator` Workflow §1 (selection
  ladder) and §4 (pick next step) now delegate to `owl next --json` and dispatch
  by `action.kind`, keeping the mutation sections (claim/adopt/heartbeat/steal/
  multi-session) as a thin reference. `owl-cli` documents `owl next` and its
  response shape. The current→pointer resolution ladder duplicated in
  `Instructions`/`Status` now reuses a shared `Tasks::Api.current_task_id`
  primitive (behavior-neutral).

## [0.1.1] - 2026-06-23

### Added
- **Communication-language clause for orchestrator/step skills.** Brought
  `owl-orchestrator`, `owl-step-discussion`, and `owl-step-execution` into
  compliance with Constitution 5.16/5.17: every user-facing string is now
  required to be emitted in `settings.language.communication`, documented once
  in `_owl_conventions.md` §7 and referenced from each skill.
- **Session-level (orchestrator) overlay.** `owl overlay show <key>` already
  resolved any key; `_owl_conventions.md` §8 reserves the `orchestrator` key as
  a session-level overlay applied to the orchestrator's end-of-run report. The
  orchestrator now reads `owl overlay show orchestrator` before its final
  summary and folds the body in.
- **Required final-report structure** in `owl-orchestrator`: what changed for
  the user / technically / verification / docs / commit / next, with an explicit
  never-omit user-facing-delta rule (technical-only tasks must say so).
- `owl init` scaffolds `.owl/overlays/orchestrator.md` (commented stub,
  `preserve_if_exists`) as a discoverable, backward-compatible extension point.

### Fixed
- `owl task child create --brief` now records `content_sha` on the seeded brief
  step, so drift detection works for pre-authored child briefs (parity with
  normal `owl step complete`).
- Synced the `workflows/{feature,composite_feature}/commit_push.context.md`
  source seeds with their materialized `.owl/` copies, which had drifted since
  the Phase-4 `owl git lock/unlock` push-serialization work. Fresh `owl init`
  now gives new projects the push-lock sequence; `owl upgrade --dry-run` is
  clean.

### Notes
- Backward compatible: projects without an `orchestrator` overlay fall back to
  the default report structure; existing step-level overlays are unchanged.
- Regression specs cover the language clause across the three skills, the
  orchestrator-overlay composition, non-step overlay-key resolution, the seeded
  brief `content_sha`, and the scaffolded orchestrator overlay.

## [0.1.0]

- Initial Owl CLI: self-hosted, spec-driven workflow engine (tasks, workflows,
  artifacts, steps, overlays, claims/locks, publish/archive).
