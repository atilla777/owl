# Owl

Owl is a personal CLI for AI-assisted, spec-driven development workflows. It
manages tasks, workflow state, artifacts, and the publishing pipeline that
turns task-local specs into durable domain documentation. Everything flows
through one CLI (`bin/owl`); agents talk to Owl via slash commands and skills
rather than touching project files directly.

This README is the practical orientation; the durable project intent and
invariants live in the `Owl Project Constitution` knowledge article in the
companion KOS application.

## What Owl is

- A spec-driven workflow runner — every task has a typed workflow
  (`feature`, `composite_feature`, `feature_slice`, `hotfix`, `research`,
  `refactor`) declared as a graph of steps in `.owl/workflows/`.
- A pluggable backend over filesystem state — `.owl/` (control plane),
  `tasks/` (active work), `tasks/archive/` (closed work), `docs/` (published
  domain docs). Backends are abstracted so the same surface can later run on
  SQLite, Obsidian, or a remote store.
- A skill harness for agents — a thin set of universal skills
  (`owl-cli`, `owl-step-run`, `owl-orchestrator`) drive any workflow without
  step-type-specific code; specialisation lives in per-step
  `.context.md` files alongside the workflow.

## Architecture (v1)

Code is organised by domain under `lib/owl/<domain>/` with three layers:

```
+------------+   +-------------------------+   +---------------------+
|  bin/owl   |-->|  Owl::<Domain>::Api     |-->| Owl::<Domain>::     |
|  (CLI thin |   |  (public facade,        |   |  Internal::*        |
|  adapter)  |   |   Result::Ok / Err)     |   |  (business logic)   |
+------------+   +-------------------------+   +---------------------+
                            |
                            v
                +-------------------------+
                |  Owl::<Domain>::Backend |  filesystem default;
                |  (interface)            |  swappable.
                +-------------------------+
```

Key invariants (excerpt from the Constitution — see `CLAUDE.md` for the full
KOS knowledge link):

- `.owl/` is the control plane; `tasks/` is the work zone (flat layout, parent
  / child wired by `parent_id` in `task.yaml`); `docs/` holds published
  domain documentation.
- Storage roles (`tasks`, `docs`, `control`, `local_state`, `index`,
  `archive`) live in `.owl/config.yaml` so workflow YAML never hardcodes
  physical paths.
- Storage / Tasks / Workflows go through a backend interface; filesystem is
  one implementation. Skills and the public `bin/owl` CLI never read or
  write `.owl/` or `tasks/` directly.
- Returns use `Owl::Result::Ok` / `Owl::Result::Err` (stdlib `Data.define`).
  Dependencies are stdlib; `dry-rb`, `interactor`, `trailblazer` and
  comparable libraries require explicit approval.

## Universal step model

Every workflow step is executed by the universal `owl-step-run` skill. The
step-specific prompt lives in a file alongside the workflow YAML:

```yaml
# .owl/workflows/feature/workflow.yaml (excerpt)
steps:
  - id: brief
    skill: owl-step-run
    context_file: brief.context.md
    creates: [brief]
```

`bin/owl step show TASK-ID brief --json` returns a merged bundle of the
step config, the resolved `context` body, the artifact template
(required sections + frontmatter schema), and the parent task's spec.
`owl-step-run` consumes that bundle and produces the declared artifact.

Adding a new step type does not require a new Ruby skill — drop a new
`<step-id>.context.md` next to `workflow.yaml` and reference it via
`context_file:`. Inline `context: "..."` is also supported when the prompt
is short.

## Skill layering

Four universal skills are seeded into `.claude/skills/` by `owl init`:

| Skill              | Layer        | Job                                                                       |
| ------------------ | ------------ | ------------------------------------------------------------------------- |
| `owl-cli`          | CLI wrapper  | Canonical interface to `bin/owl`.                                         |
| `owl-step-run`     | Executor     | Runs any ready step from `owl step show` bundle.                          |
| `owl-orchestrator` | Coordinator  | Picks the next ready step, delegates execution.                           |
| `owl-init`         | Bootstrap    | One-shot wizard that fills `.owl/config.yaml` `settings:` via Q&A + CLI.  |

Three slash-commands (`owl-task-create`, `owl-task-status`, `owl-task-next`)
sit next to the skills under `.claude/commands/`.

No skill reads `.owl/`, `tasks/`, or `docs/` directly. The `bin/owl` CLI is
the only sanctioned interface to Owl project state.

## CLI surface

Use `bin/owl <subcommand> --json` for machine output. Common subcommands:

- `owl init [--root PATH] [--force]` — materialise `.owl/`, seeded
  workflows + per-step `.context.md`, seeded skills, starter artifact
  templates.
- `owl workflow list --json` — list declared workflows.
- `owl config get KEY [--json]` — read a value at a `settings.*` dot-path.
- `owl config set KEY VALUE [--json]` — write a value at a `settings.*`
  dot-path; the call validates the resulting config before writing and
  rolls back on failure. JSON-array literals (`'["a","b"]'`) are accepted
  for list values.
- `owl config show [--json]` — full `settings:` + storage roles snapshot.
- `owl config validate --json` — JSON Schema check for `.owl/config.yaml`.
- `owl task create --workflow KEY --title "..." [--json]` /
  `owl task child create --parent ID --workflow KEY --title "..."` —
  spawn a task or child task.
- `owl task list / inspect / use / current / tree / children / parent /
  aggregate-status / split / index rebuild` — task discovery and lifecycle.
- `owl task ready-steps TASK-ID --json` — next ready steps from the
  workflow graph.
- `owl step show TASK-ID STEP-ID --json` — merged step + context +
  artifact_template + task bundle (preferred for `owl-step-run`).
- `owl step start / complete / skip` — step transitions.
- `owl step invocation TASK-ID STEP-ID --json` — raw StepInvocation
  payload used by `owl instructions`.
- `owl artifact resolve / validate` — task-scoped artifact path and
  template validation.
- `owl publish TASK-ID --json` — apply the workflow's `publishes` rules
  to copy approved artifacts under `docs/`.
- `owl archive TASK-ID --json` — move a finished task (and its subtree
  for composites) under `tasks/archive/<date>-<TASK-ID>-<slug>/`.
- `owl instructions TASK-ID [--step-id STEP] --json` — package the next
  ready step with its SKILL.md summary for agent delegation.
- `owl status TASK-ID --json` — agent-friendly progress summary
  (per-step `ready` flag, `progress {done, total, pct}`, blockers,
  composite children).

Run `bin/owl --help` (or any subcommand with `--help`) for the full list.

## Authoring a workflow

1. Choose a key (`my_workflow`) and add it to `.owl/workflows.yaml`:

   ```yaml
   workflows:
     my_workflow:
       enabled: true
       title: My workflow
       source: "workflows/my_workflow/workflow.yaml"
   ```

2. Create `.owl/workflows/my_workflow/workflow.yaml`:

   ```yaml
   id: my_workflow
   kind: task
   artifacts:
     spec:
       type: spec
       storage:
         role: tasks
         path: "{{task.id}}/spec.md"
   steps:
     - id: specify
       skill: owl-step-run
       context_file: specify.context.md
       creates: [spec]
   ```

3. Drop `.owl/workflows/my_workflow/specify.context.md` next to the YAML
   with the per-step prompt the agent should follow when running
   `owl-step-run`.

4. `owl config validate --json` and `owl workflow list --json` should pick
   up the new entry without restart.

## Composite tasks

`composite_feature` (and any future composite-shaped workflow) decomposes
into child tasks tracked by `parent_id`. Three composite-specific steps:

- `decompose` — produces `decomposition.md` plus child tasks (via
  `owl task child create --parent PARENT-ID --workflow feature_slice ...`).
- `coordinate` — tracks child readiness; surfaces blockers.
- `aggregate_verify` — rolls up child `verification.md` reports into the
  parent's `verification` artifact.

`owl archive PARENT-ID --json` archives the parent and every ready child
atomically. If any child is not ready, the call returns
`composite_with_unready_children` (with a list of missing steps) instead
of partial archive.

## KOS integration

This repository is connected to KOS — the authoritative source of agent
workflow state (tasks, specs, plans, verification, review, completion
reports, git trace). See `CLAUDE.md` for the bootstrap entrypoint, the
installed `kos-*` slash commands, and the runtime endpoint.

Historical Markdown (`AGENTS.md`, `ARCHITECTURE.md`, `REQUIREMENTS.md`,
`IMPLEMENTATION_PLAN.md`) is preserved as readable fallback only; the
`Owl Project Constitution` KOS knowledge article is the active operating
law.

## Testing

```bash
bundle exec rspec
bundle exec rubocop
```

Do not use `rubocop -A` — `Style/StringConcatenation` autocorrect rewrites
`Pathname + String` into broken string interpolation. The cop is disabled
in `.rubocop.yml`, but `-A` would silently re-enable it for the diff.

## Layout

```
.
├── bin/owl                       # CLI entrypoint (thin)
├── lib/owl/
│   ├── result.rb                 # Owl::Result::Ok / Err
│   ├── cli/                      # CLI dispatch + subcommand handlers
│   ├── config/                   # .owl/config.yaml loader + validator
│   ├── tasks/                    # task lifecycle + Tasks::Backend
│   ├── workflows/                # workflow registry + per-step context
│   ├── artifacts/                # artifact registry + templates
│   ├── steps/                    # step invocation + show bundle
│   ├── storage/                  # filesystem storage role resolver
│   ├── archive/                  # archive subtree + slug generator
│   ├── publish/                  # publishes rules
│   ├── skills/                   # seeded skills + slash-commands
│   ├── instructions/             # next-step packaging
│   ├── validation/               # artifact validation
│   └── schemas/                  # JSON Schemas for workflow / config
├── spec/owl/...                  # RSpec
├── CLAUDE.md                     # KOS bootstrap entrypoint
├── AGENTS.md / ARCHITECTURE.md / REQUIREMENTS.md / IMPLEMENTATION_PLAN.md
│   # historical fallback — see CLAUDE.md
└── README.md                     # this file
```
