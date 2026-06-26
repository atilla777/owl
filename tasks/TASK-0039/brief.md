---
status: draft
summary: Sync agent-facing docs (CLAUDE.md, owl-cli) with the real CLI surface and collapse the redundant per-step orchestrator loop.
---

# Brief

## Problem

The agent-instruction layer drifted from the CLI:
- `CLAUDE.md` "Startup Sequence" never mentions `owl next` (the orchestrator's
  canonical entrypoint) and its "Mutating commands" list omits the whole
  concurrency model (claim/release/heartbeat/adopt, commit-push, plan approve,
  step reset).
- `skills/owl-cli/SKILL.md` lists a stale command subset yet its stop-condition
  says "if a command is not listed here or in `--help`, do not invent it" — so a
  literal agent stalls on the very first `owl task claim`. It also carries a
  reliclt KOS reference (`:37`).
- The per-step loop is heavier than needed: ~13-15 CLI calls to advance one
  execution step, with `session_type` resolved 3× (`next`→`instructions`→`step show`)
  and `step show` / `artifact validate` / `step complete` each called 2×.
  `step complete` is idempotent (verified), but the skill never says so, so a
  no-op re-complete can look like an error.
- `owl-step-execution` report vocabulary is inconsistent: frontmatter enum
  `status: returned_normally|do_not_use|error` vs prose `final_state: interrupted|error`.
- Orchestrator step numbering skips "5".

## Goal

An agent bootstrapping from CLAUDE.md or owl-cli gets the same, current mental
model the orchestrator assumes, and advances a step in noticeably fewer CLI calls
with no ambiguity about who owns completion/validation.

## Scenarios

### Requirement: Docs match the CLI
The agent-facing docs SHALL reference `owl next` as the canonical next-action call
and SHALL not instruct the agent to stop on commands present in `owl --help`.

#### Scenario: Agent reads owl-cli then runs the loop
- WHEN an agent follows owl-cli literally and needs `owl task claim`
- THEN nothing in the skill tells it to stop, because the command is reachable via `owl --help`

### Requirement: Single completion owner
The orchestrator SHALL state that the executor owns `owl step complete` + final
`artifact validate`, and that a `step_not_running`/idempotent re-complete is success.

#### Scenario: Orchestrator re-completes a done step
- WHEN the executor already completed the step and the orchestrator re-issues `owl step complete`
- THEN it is treated as an idempotent safety re-check, not an error

### Requirement: One report-status vocabulary
The execution report contract SHALL use a single status field whose enum covers
the interrupted/human-needed case.

#### Scenario: Subagent needs human input
- WHEN an execution subagent must stop for human input
- THEN it writes one canonical status value defined in the contract (no `final_state` vs `status` ambiguity)

## Edge cases

- Custom (non-seeded) workflows may bind their own skills — guidance must stay generic.
- Keep CLAUDE.md concise; link to skills rather than duplicating the full surface.

## Acceptance criteria

- CLAUDE.md Startup Sequence includes `owl next`; Mutating-commands list includes
  the concurrency + plan + commit-push + step reset surface.
- owl-cli stop-condition reworded to "fall back to `owl --help`"; KOS line removed;
  command list refreshed.
- Orchestrator documents single completion owner + idempotent re-check; numbering fixed.
- Execution report uses one status field/enum; `_owl_conventions.md` aligned.
- Version bump (minor) + CHANGELOG.
