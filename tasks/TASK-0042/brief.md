---
status: approved
summary: Add a machine-level `owl self-update` command that rebuilds and installs the owl-cli gem from a configured source path, separate from the project-scoped `owl upgrade`.
---

# Problem

Propagating an Owl source change to consumer projects (`re`/Rrrog, `tetris`)
today requires two machine-global steps before the per-project sync:

```
gem build owl-cli.gemspec && gem install owl-cli-<version>.gem   # machine-global
owl upgrade                                                       # per consumer project
```

The build+install step has no first-class command: the operator must remember
the gemspec name and the exact built-gem filename (which embeds the version).
`owl upgrade` is correctly **project-scoped** — it re-materialises skills /
commands / seed content from whatever CLI is already on `PATH` and deliberately
does **not** mutate the global gem. So there is no Owl-native way to advance the
installed gem; the friction lives entirely outside the tool.

A naive fix — folding the gem install into `owl upgrade` — is wrong on three
counts: (1) it couples a project-scoped operation with a machine-global
mutation, so running `owl upgrade` in `tetris` could silently change the CLI
used by `re`; (2) the currently-installed gem cannot self-update to a version
whose logic it does not yet contain (bootstrap / chicken-and-egg); (3) `upgrade`
has no notion of "where does a newer gem come from".

# Goal

Add a distinct, **machine-level** command `owl self-update` that rebuilds and
installs the `owl-cli` gem from a configured source, leaving `owl upgrade`
unchanged as the project-scoped content sync. The end-to-end propagation
becomes:

```
owl self-update     # rebuild + install the gem on PATH (machine-global)
owl upgrade         # re-materialise content in each consumer project
```

Scope for this task (v1):

- Source is a **local checkout path** resolved from config
  (`settings.distribution.source_path`); when `self-update` is invoked from
  inside an Owl checkout, the repo root is the implicit default. A git-ref
  source is explicitly **out of scope** (future work).
- The command runs `gem build <gemspec>` then `gem install <built gem>` in the
  resolved source, reports the old→new version, and reminds the operator to run
  `owl upgrade` in consumer projects.
- The shell-out to `gem` is performed through an injectable runner (mirroring
  the existing `GitRunner` pattern) so the behaviour is unit-testable without
  mutating the host gem environment.
- The command is purely **additive**: a new CLI verb plus one new optional
  config key. No existing command, JSON shape, schema, or seeded template
  changes → minor version bump.

Explicitly acknowledged limitation (not a bug to fix here): the gem currently on
`PATH` (0.20.0) predates this command, so the **first** hop to the version that
ships `self-update` must still be done manually. From that version onward,
self-update is available.

# Scenarios

### Requirement: Self-update command exists and is machine-scoped

The system SHALL provide an `owl self-update` command that rebuilds and installs
the `owl-cli` gem from a configured source without modifying the current
project's materialised content.

#### Scenario: Successful self-update from a configured source
- WHEN the operator runs `owl self-update` and `settings.distribution.source_path` resolves to a valid Owl checkout containing `owl-cli.gemspec`
- THEN the command builds the gem from that source and installs it onto the active gem environment
- AND it reports the previously-installed version and the newly-installed version
- AND it prints a reminder to run `owl upgrade` in consumer projects

#### Scenario: Source path defaults to the current checkout
- WHEN the operator runs `owl self-update` from inside an Owl source checkout and `settings.distribution.source_path` is unset
- THEN the command uses the checkout root as the build source
- AND it proceeds with build + install as in the success case

### Requirement: Self-update is separate from project upgrade

The system SHALL NOT change the behaviour of `owl upgrade`, which remains
project-scoped and does not build or install the gem.

#### Scenario: upgrade still only syncs project content
- WHEN the operator runs `owl upgrade` after this change
- THEN it re-materialises skills/commands/seed content from the CLI already on PATH exactly as before
- AND it does not invoke `gem build` or `gem install`

### Requirement: Missing or invalid source is a structured error

The system SHALL fail with a structured error code and actionable guidance when
the source cannot be resolved or does not contain a buildable gemspec.

#### Scenario: Source path unset and not in a checkout
- WHEN the operator runs `owl self-update` with `settings.distribution.source_path` unset and the working directory is not an Owl checkout
- THEN the command exits non-zero with a structured error identifying the missing source
- AND it does not invoke `gem build` or `gem install`

#### Scenario: Build or install fails
- WHEN `gem build` or `gem install` exits non-zero (e.g. compile error, permission denied)
- THEN the command surfaces the underlying command's exit status and stderr in a structured error
- AND it leaves any previously-installed gem version in place (no partial/destroyed state introduced by Owl)

### Requirement: Dry-run preview

The system SHOULD support a `--dry-run` flag that reports the resolved source,
the gemspec, and the build/install commands it would run, without mutating the
gem environment.

#### Scenario: Dry-run prints the plan only
- WHEN the operator runs `owl self-update --dry-run`
- THEN the command prints the resolved source path and the build+install commands it would execute
- AND it does not invoke `gem build` or `gem install`

# Edge cases

- **Bootstrap (first hop).** The installed 0.20.0 gem has no `self-update`; the
  manual `gem install` of the first version that ships this command is required
  and is documented, not worked around.
- **Same version reinstall.** Running `self-update` when the source version
  equals the installed version performs a reinstall (idempotent in effect); the
  report shows identical old/new versions rather than erroring.
- **gem executable resolution.** The `gem` binary is resolved from the active
  Ruby/mise environment; the injectable runner makes this overridable for tests.
- **Permissions.** `gem install` may need write access to the gem dir; a
  permission failure is surfaced as a structured error, not a stack trace.
- **Concurrency.** `self-update` is machine-global and unrelated to task
  claims / per-task step locks / the repo push lock; it takes none of them. Two
  concurrent self-updates are out of scope (operator discipline).

# Acceptance criteria

- `owl self-update` exists, builds and installs the gem from the resolved
  source, and reports old→new version plus an `owl upgrade` reminder.
- Source resolution: explicit `settings.distribution.source_path`, else the
  current checkout root, else a structured `source unresolved` error.
- `--dry-run` previews the plan and mutates nothing.
- `gem` invocation goes through an injectable runner (no host-gem mutation in
  unit tests); build/install failures map to structured error codes with the
  underlying exit status surfaced.
- `owl upgrade` behaviour is unchanged (regression-covered).
- New public surface under `lib/owl/**/api.rb` has 100% line coverage per
  `docs/agents/30_Owl_Ruby_testing_RSpec_and_public_API_coverage.md`.
- Change is additive only → `Owl::VERSION` minor bump + `CHANGELOG.md` entry in
  the delivery commit; new config key documented.
- Layering respected (`docs/agents/27_Owl_Ruby_code_architecture.md`): no raw
  `.owl/` FS access outside the Backend layer; config read through the existing
  config accessor.

## Overlay checklist disposition

- **Source-of-truth & layering** — config read via the existing config
  accessor; no new raw `.owl/` FS reads. New command lives in the CLI/Api layer
  delegating to a service object; shell-out isolated in a runner (Backend).
- **Public API surface & coverage** — adds a `self_update` Api entrypoint;
  specs will cover it to 100% line coverage.
- **Backward compatibility** — additive command + one optional config key; no
  managed workflow/artifact/schema/template change. Minor bump.
- **Security & data access** — new reach is local shell-out to `gem build` /
  `gem install` against a configured/trusted source path; no network in v1, no
  secrets, no destructive git.
- **Concurrency** — machine-global; takes no claim/step/push lock; documented.
- **Error handling** — structured codes for unresolved source, missing gemspec,
  build failure, install failure; non-zero exit; reinstall is idempotent.
- **Constitution** — additive, version-bumped, test-covered; respects
  managed-by-cloning and layering invariants.
