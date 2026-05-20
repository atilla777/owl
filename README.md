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
  (`feature` for a single feature, `composite_feature` for one
  decomposed into child tasks) declared as a graph of steps in
  `.owl/workflows/`. Bug-fix and refactor framings are step **variants**
  of `brief` (see "Step variants" below), not separate workflows.
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

### Step variants

A step can declare alternative implementations via a `variants:` block.
At runtime the task records its choice (`step_variants: { brief: ... }`
in `task.yaml`); the resolver picks the corresponding `context_file`
and the overlay collector also loads
`.owl/overlays/<step>/<variant>.md` and `docs/ai/<step>/<variant>.md`
on top of the universal `<step>.md` overlays.

```yaml
steps:
  - id: brief
    skill: owl-step-run
    default_variant: feature
    variants:
      feature:           # collect requirements (default)
        context_file: brief.feature.context.md
      root_cause:        # bug-fix framing — RCA brief
        context_file: brief.root_cause.context.md
      problem_inventory: # refactor framing — problem list
        context_file: brief.problem_inventory.context.md
```

Choose the variant at task create time (`--variant brief=root_cause`)
or at step start (`owl step start TASK brief --variant root_cause`).
Downstream steps read `brief.variant` from the artifact's front matter
and adapt their own instructions.

## Skill layering

Five universal skills are seeded into `.claude/skills/` by `owl init`:

| Skill              | Layer        | Job                                                                       |
| ------------------ | ------------ | ------------------------------------------------------------------------- |
| `owl-cli`          | CLI wrapper  | Canonical interface to `bin/owl`.                                         |
| `owl-step-run`     | Executor     | Runs any ready step from `owl step show` bundle.                          |
| `owl-orchestrator` | Coordinator  | Picks the next ready step, delegates execution.                           |
| `owl-init`         | Bootstrap    | One-shot wizard that fills `.owl/config.yaml` `settings:` via Q&A + CLI.  |
| `owl-author`       | Authoring    | Q&A skill that creates / edits workflow + artifact-type definitions.      |

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
- `owl workflow new --id ID [--kind task|composite_task] [--from TEMPLATE_ID] [--body -] [--force] [--json]` —
  scaffold a new workflow source at `.owl/workflows/<id>/workflow.yaml`. Default body
  is a minimal seed; pass `--body -` to pipe a full YAML body on stdin (the CLI
  validates before writing and writes nothing on failure). Does not modify
  `.owl/workflows.yaml` — registration is an explicit follow-up step.
- `owl workflow validate ID-OR-PATH [--json]` — validate a workflow by registry id
  or by source path (JSON Schema-style shape check + graph + cycle + artifact-ref check).
- `owl workflow show ID [--json]` — full registry entry + parsed YAML body for a
  registered workflow.
- `owl artifact-type list [--json]` — list declared artifact types.
- `owl artifact-type new --id ID [--body -] [--force] [--json]` — scaffold a new
  artifact-type source at `.owl/artifacts/<id>/artifact.yaml` plus a minimal
  `templates/default.md`. Same validate-before-write semantics as `workflow new`.
- `owl artifact-type validate ID-OR-PATH [--json]` — validate an artifact-type
  definition by registry id or path.
- `owl artifact-type show ID [--json]` — full definition body for a registered
  artifact-type.
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

The fastest path is the agent-driven `owl-author` skill (loaded via the
`/owl-author` slash-command after `owl init`). It walks you through three
modes — create workflow, create artifact-type, edit existing — via Q&A
and persists every change through the `bin/owl workflow|artifact-type` CLI
(no direct YAML editing). It respects `settings.language.communication`
for the dialogue and `settings.language.artifacts` for template content;
`required_sections` stay in English (constitution 5.16).

If you'd rather scaffold by hand:

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

## Seeded sources

The top-level `skills/`, `commands/`, `workflows/`, `artifacts/`, and
`schemas/` directories are the *seeded* defaults Owl materializes into a
target project on `owl init`. They are plain files — readable and
editable in any editor without going through the Ruby code, and copyable
by hand if you ever need to bootstrap a project without `bin/owl`.

| Repo path                       | Materialized to                       |
| ------------------------------- | ------------------------------------- |
| `skills/owl-*/SKILL.md`         | `.claude/skills/owl-*/SKILL.md`       |
| `commands/owl-*.md`             | `.claude/commands/owl-*.md`           |
| `workflows/<id>/workflow.yaml`  | `.owl/workflows/<id>/workflow.yaml`   |
| `workflows/<id>/*.context.md`   | `.owl/workflows/<id>/*.context.md`    |
| `artifacts/<id>/artifact.yaml`  | `.owl/artifacts/<id>/artifact.yaml`   |
| `artifacts/<id>/templates/*.md` | `.owl/artifacts/<id>/templates/*.md`  |
| `schemas/*.json`                | (not copied — used in-process)        |

Do not confuse repo-root `skills/` (Owl defaults, the seed) with
`.claude/skills/kos-*` (KOS skills used while *developing* Owl itself —
a separate concept, not part of what Owl ships).

## Layout

```
.
├── bin/owl                       # CLI entrypoint (thin)
├── skills/                       # seeded Owl-owned skills (SKILL.md per name)
├── commands/                     # seeded slash-commands for the skills above
├── workflows/                    # seeded default workflows + per-step .context.md
├── artifacts/                    # seeded artifact types + default Markdown templates
├── schemas/                      # JSON Schemas (workflow / artifact / step_invocation)
├── lib/owl/
│   ├── result.rb                 # Owl::Result::Ok / Err
│   ├── internal/                 # cross-domain helpers (Paths, SeededLoader)
│   ├── cli/                      # CLI dispatch + subcommand handlers
│   ├── config/                   # .owl/config.yaml loader + validator
│   ├── tasks/                    # task lifecycle + Tasks::Backend
│   ├── workflows/                # workflow registry + per-step context
│   ├── artifacts/                # artifact registry + templates
│   ├── steps/                    # step invocation + show bundle
│   ├── storage/                  # filesystem storage role resolver
│   ├── archive/                  # archive subtree + slug generator
│   ├── publish/                  # publishes rules
│   ├── skills/                   # thin loader over repo-root skills/ + commands/
│   ├── instructions/             # next-step packaging
│   └── validation/               # artifact validation
├── spec/owl/...                  # RSpec
├── CLAUDE.md                     # KOS bootstrap entrypoint
├── AGENTS.md / ARCHITECTURE.md / REQUIREMENTS.md / IMPLEMENTATION_PLAN.md
│   # historical fallback — see CLAUDE.md
└── README.md                     # this file
```
