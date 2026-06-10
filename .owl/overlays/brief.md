# Brief completeness checklist (Owl project overlay)

Before setting the brief's front matter to `status: approved`, walk this
checklist. For each item, either fold the answer into the brief (Scenarios /
Edge cases / Acceptance criteria) or state explicitly that it does not apply.
If an item materially affects scope or correctness and the request leaves it
ambiguous, treat it as a real blocker (`_owl_conventions.md` §2) and ask the
user rather than guessing.

- **Source-of-truth & layering** — does the change touch `.owl/`, `tasks/`, or
  `docs/` access paths? It must go through `bin/owl`, never raw FS reads. See
  `docs/agents/27_Owl_Ruby_code_architecture.md` (Backend/Internal/Api layering
  and FS-access rules).
- **Public API surface & coverage** — does it add or change `lib/owl/**/api.rb`?
  Those files require 100% line coverage (`docs/agents/30_Owl_Ruby_testing_RSpec_and_public_API_coverage.md`);
  name the specs that will cover the new lines.
- **Backward compatibility (upgrade-safety)** — does it change managed
  workflows/artifacts, the workflow/artifact JSON schemas, the `bin/owl` JSON
  response shapes, or seeded templates under `workflows/` & `artifacts/`?
  Managed (Owl-shipped) definitions are customised by cloning, not editing —
  preserve that contract.
- **Security & data access** — new filesystem/network reach, secrets, or
  destructive git operations (push to a shared remote, deletions).
- **Concurrency** — does it interact with task claims, per-task step locks,
  heartbeats/TTL, or the repo-scoped push lock? State the multi-session
  behaviour.
- **Error handling** — failure modes, structured error codes, CLI exit codes,
  and idempotency of mutating commands.
- **Constitution** — confirm the change respects
  `docs/agents/23_Owl_Project_Constitution.md` (non-negotiable rules).

Replace or extend these items as the project's conventions evolve.
