# Owl

Owl is a personal CLI that lets AI agents drive software work through
**typed, declarative workflows**. You describe a task (a feature, a bug
investigation, a refactor, a composite initiative), and Owl walks an agent
through the right steps in order — collect a brief, write a design, plan,
implement, verify, review, publish docs, archive — producing a small set
of well-formed Markdown artifacts at every step.

Everything goes through a single CLI (`owl`, packaged as the
`owl-cli` Ruby gem). Agents never touch `.owl/` or `tasks/` files
directly; they read and mutate state via `owl <subcommand> --json`.
That single rule is what makes Owl swappable underneath (filesystem
today, SQLite / Obsidian / remote tomorrow) and safe to delegate to
LLMs.

## Quick start

```bash
# from this repository
gem build owl-cli.gemspec
gem install ./owl-cli-*.gem

# in your target project
cd /path/to/your/project
owl init               # materialize .owl/, skills, commands, seeded workflows
                       # → ready to use: workflows `feature` and `composite_feature`
                       #   are enabled, default language is `en`.

# Optional — customize language, storage paths, enabled-workflow filter.
# Inside Claude Code (agent loads the `owl-init` skill, asks via AskUserQuestion):
/owl-init

# Create the first task and drive it end-to-end (agent-invokable):
/owl-task-create feature "My first feature"
/owl-orchestrator
```

The `/owl-*` slash commands are not user-only — they are the human-typing
handle for skills the AI agent invokes itself via its `Skill` tool. User
interactivity inside a skill happens through the harness Q&A surface
(`AskUserQuestion`), not by waiting for the user to type the command.

See [For AI agents: installing Owl in a target project](#for-ai-agents-installing-owl-in-a-target-project)
for the full install recipe.

## What Owl gives you

- **Workflow-driven task lifecycle.** Built-in `feature` and
  `composite_feature` workflows; each is a graph of typed steps. Bug
  and refactor framings are not separate workflows — they are
  **variants** of the `brief` step.
- **Declarative artifacts.** Every step declares which artifact(s) it
  produces; each artifact type has a Markdown template, a required-
  section list, and frontmatter schema. Artifacts are validated on
  step completion.
- **Universal step model.** All steps share one executor skill
  (`owl-step-run`). The per-step prompt lives in a `.context.md` file
  next to the workflow YAML. Adding a new step type = dropping a new
  Markdown file, no Ruby code.
- **Composite tasks.** A `composite_feature` decomposes into child
  tasks linked by `parent_id`; the parent tracks aggregate readiness
  and archives the whole subtree atomically.
- **Publishing pipeline.** A workflow can declare `publishes:` rules
  to copy approved artifacts from a task tree into `docs/` (durable
  domain documentation).
- **Pluggable storage.** Storage roles (`tasks`, `docs`, `archive`,
  `control`, `local_state`, `index`) live in `.owl/config.yaml`;
  workflow YAML never hard-codes physical paths.
- **Slash-command surface for agents.** `owl init`, `owl-task-create`,
  `owl-task-next`, `owl-orchestrator`, `owl-step-run`, `owl-author`
  are installed into `.claude/` so any Claude Code session in the
  project can drive Owl end-to-end.

## How it works

```
                ┌──────────────────┐
   user / LLM ──▶  /owl-* slash    │
                │  commands        │
                └────────┬─────────┘
                         ▼
                ┌──────────────────┐
                │  Owl skills      │  owl-orchestrator → owl-step-run
                │  (.claude/skills)│  (decide / execute)
                └────────┬─────────┘
                         ▼
                ┌──────────────────┐
                │  bin/owl CLI     │  the ONLY interface to project state
                │  --json contract │
                └────────┬─────────┘
                         ▼
   ┌──────────────┬──────────────┬──────────────┬──────────────┐
   │  .owl/       │  tasks/      │  docs/       │  tasks/      │
   │  control     │  active      │  published   │  archive/    │
   │  plane       │  work        │  domain docs │  closed work │
   └──────────────┴──────────────┴──────────────┴──────────────┘
```

The loop is always the same:

1. **Create a task** with a workflow key (`feature`, `composite_feature`)
   and a title — optionally choosing a `brief` variant.
2. **Ask the orchestrator** for the next ready step
   (`owl task ready-steps`).
3. **Execute the step.** `owl step show TASK-ID STEP-ID --json` returns
   a self-contained bundle — step config + the resolved per-step prompt
   + the artifact template + the task spec. `owl-step-run` follows the
   prompt and writes the artifact at the resolved path.
4. **Complete the step.** Owl re-validates the artifact (required
   sections, frontmatter schema, regex rules) before advancing.
5. **Loop** until the workflow's terminal step (`archive` /
   `commit_push`) is done.

## Architecture

Code is organised by domain under `lib/owl/<domain>/` with three layers:

```
+------------+   +-------------------------+   +---------------------+
|  bin/owl   |-->|  Owl::<Domain>::Api     |-->| Owl::<Domain>::     |
|  (thin     |   |  (public facade,        |   |  Internal::*        |
|  CLI       |   |   Result::Ok / Err)     |   |  (business logic)   |
|  adapter)  |   +-------------------------+   +---------------------+
+------------+              |
                            v
                +-------------------------+
                |  Owl::<Domain>::Backend |  filesystem default;
                |  (interface)            |  swappable.
                +-------------------------+
```

Returns use `Owl::Result::Ok` / `Owl::Result::Err` (`Data.define`).
Dependencies are stdlib by default (`dry-rb`, `interactor`, etc.
require explicit approval).

### Where the files live

After `owl init`, an Owl-managed project has this shape:

| Location                                  | Purpose                                                                 |
| ----------------------------------------- | ----------------------------------------------------------------------- |
| `bin/owl`                                 | CLI entrypoint — the only sanctioned interface to project state.        |
| `.owl/config.yaml`                        | Control plane — storage role paths, language, enabled workflows.        |
| `.owl/workflows.yaml`                     | Workflow registry — `key → source path` for each enabled workflow.      |
| `.owl/artifacts.yaml`                     | Artifact-type registry — `key → source path` for each artifact type.    |
| `.owl/workflows/<id>/workflow.yaml`       | Declared workflow (steps, artifacts, publishes, variants).              |
| `.owl/workflows/<id>/<step>.context.md`   | Per-step prompt the universal executor follows.                         |
| `.owl/artifacts/<type>/artifact.yaml`     | Artifact-type definition (frontmatter schema, required sections).       |
| `.owl/artifacts/<type>/templates/*.md`    | Markdown templates for each artifact type.                              |
| `.owl/overlays/<step>.md`                 | Cross-workflow overlay merged into the step prompt (one per step id).   |
| `.owl/local/current.yaml`                 | "Current task" pointer (per-clone, not committed).                      |
| `tasks/<TASK-ID>/task.yaml`               | Task state — workflow key, step statuses, variants, parent_id.          |
| `tasks/<TASK-ID>/{brief,design,plan,…}.md`| Active task artifacts.                                                  |
| `tasks/index.yaml`                        | Cached task index (rebuildable via `owl task index rebuild`).           |
| `tasks/archive/<date>-<TASK-ID>-<slug>/`  | Archived tasks (composite subtrees archived atomically).                |
| `docs/`                                   | Published domain documentation (output of `owl publish`).               |
| `docs/ai/<step>/<variant>.md`             | Optional variant-specific overlay merged on top of `.owl/overlays/`.    |
| `.claude/skills/owl-*/SKILL.md`           | Owl skills loaded by Claude Code sessions.                              |
| `.claude/skills/_owl_conventions.md`      | Shared conventions doc referenced by every Owl skill.                   |
| `.claude/commands/owl-*.md`               | Slash commands that load the skills above.                              |

### Repo-root seeds

This repository's top-level `skills/`, `commands/`, `workflows/`,
`artifacts/`, and `schemas/` directories are the *seeded defaults*
Owl materializes into a target project on `owl init`:

| Repo path                       | Materialized to                       |
| ------------------------------- | ------------------------------------- |
| `skills/owl-*/SKILL.md`         | `.claude/skills/owl-*/SKILL.md`       |
| `commands/owl-*.md`             | `.claude/commands/owl-*.md`           |
| `workflows/<id>/workflow.yaml`  | `.owl/workflows/<id>/workflow.yaml`   |
| `workflows/<id>/*.context.md`   | `.owl/workflows/<id>/*.context.md`    |
| `artifacts/<id>/artifact.yaml`  | `.owl/artifacts/<id>/artifact.yaml`   |
| `artifacts/<id>/templates/*.md` | `.owl/artifacts/<id>/templates/*.md`  |
| `schemas/*.json`                | (not copied — used in-process)        |

JSON Schemas under `schemas/` (`workflow.json`, `artifact.json`,
`step_invocation.json`) are validated in-process — they constrain
what a workflow / artifact / step bundle is allowed to look like.

### Universal step model

```yaml
# .owl/workflows/feature/workflow.yaml (excerpt)
steps:
  - id: brief
    skill: owl-step-run
    default_variant: feature
    variants:
      feature:           # collect requirements (default)
        context_file: brief.feature.context.md
      root_cause:        # bug-fix framing
        context_file: brief.root_cause.context.md
      problem_inventory: # refactor framing
        context_file: brief.problem_inventory.context.md
  - id: plan
    skill: owl-step-run
    context_file: plan.context.md
    requires: [brief]
    creates: [plan]
```

`owl step show TASK-ID brief --json` returns a merged bundle (step
config + resolved `context` body + artifact template + parent task
spec). `owl-step-run` consumes that bundle and produces the declared
artifact at the path returned by `owl artifact resolve`.

## CLI usage example

A typical end-to-end run from a Claude Code session inside an
Owl-managed project. Slash commands are shown as the agent sees them;
each one loads the matching skill and calls the CLI underneath.

```bash
# 1. One-time bootstrap (the agent runs the wizard for you)
/owl-init
# → asks for communication language, artifact language, storage role
#   paths, enabled workflows; writes everything via `owl config set`.

# 2. List the workflows available in this project
owl workflow list --json

# 3a. Create a new feature task (default variant)
/owl-task-create feature "Add per-user rate limiting"
# → owl task create --workflow feature --title "Add per-user rate limiting"

# 3b. Or a bug-fix framing — same workflow, different brief variant
owl task create --workflow feature \
  --title "Fix 502 on /reports during peak load" \
  --variant brief=root_cause --json

# 3c. Or a refactor framing
owl task create --workflow feature \
  --title "Inventory and untangle Invoicing::Engine" \
  --variant brief=problem_inventory --json

# 3d. Or a big initiative that decomposes into child tasks
owl task create --workflow composite_feature \
  --title "Multi-tenant data isolation" --json

# 4. Drive the task end-to-end
/owl-orchestrator
# The orchestrator:
#   • reads `owl task ready-steps TASK-ID --json`
#   • picks the first ready step (e.g. `brief`)
#   • calls `owl step show TASK-ID brief --json` for the bundle
#   • delegates to `owl-step-run`, which writes brief.md
#   • runs `owl artifact validate TASK-ID brief --json`
#   • runs `owl step complete TASK-ID brief`
#   • loops to the next step (design → plan → implement → review_code …)

# 5. Inspect progress at any time
owl status TASK-ID --json
# → { steps: [...], progress: {done, total, pct}, blockers: [...], children: [...] }

# 6. For composite tasks, walk the subtree
owl task tree TASK-ID --json
owl task aggregate-status PARENT-ID --json
owl task child create --parent PARENT-ID --workflow feature \
  --title "Slice 1: enforce tenant_id in repository layer"

# 7. Publish approved artifacts into docs/
owl publish TASK-ID --json

# 8. Archive a finished task (or subtree, for composites)
owl archive TASK-ID --json
```

Common read-only commands an agent uses:

```bash
owl task list --json                   # all tasks
owl task current --json                # current task pointer
owl task inspect TASK-ID --json        # raw task.yaml payload
owl task ready-steps TASK-ID --json    # next ready steps
owl step show TASK-ID STEP --json      # step + context + template bundle
owl artifact resolve TASK-ID TYPE --json
owl artifact validate TASK-ID TYPE --json
owl config show --json
owl workflow show ID --json
```

## For AI agents: installing Owl in a target project

These instructions are for an AI agent (Claude Code or similar) tasked
with adding Owl to a project. Follow them in order; do not skip steps.

### 1. Prerequisites

- Ruby 3.3.x available on `PATH` (see `.ruby-version` in this repo).
- The project to install into is a git working tree (Owl writes
  `.owl/`, `tasks/`, and `.claude/` inside the project root).

### 2. Install the `owl` CLI

Owl is distributed as a Ruby gem named **`owl-cli`** (the gem ships
the `owl` executable plus all seed files for `owl init`).

**Recommended — install from a built `.gem`:**

```bash
# from this repository's checkout
gem build owl-cli.gemspec          # produces owl-cli-<version>.gem
gem install ./owl-cli-*.gem        # puts `owl` on PATH

owl --version                      # → owl 0.1.0
```

**Alternative — Bundler in the target project:**

```ruby
# target project's Gemfile
gem 'owl-cli', path: '/abs/path/to/owl-checkout'
# or, once published:
# gem 'owl-cli'
```

Then `bundle exec owl …` inside the target project.

**Dev-mode alternatives** (no `gem install`, useful when hacking on Owl
itself):

- symlink: `ln -s /path/to/owl-checkout/bin/owl ~/.local/bin/owl`
- absolute path: invoke `/abs/path/to/owl/bin/owl …` directly

The gem packages `bin/owl`, `lib/owl/**`, plus the seed directories
`skills/`, `commands/`, `workflows/`, `artifacts/`, and `schemas/`,
so a clean `gem install` is fully self-contained — `owl init` resolves
seed paths relative to the installed gem location.

### 3. Materialize `.owl/`, skills, and commands

Run the CLI bootstrap from the target project root:

```bash
owl init
```

This is **non-destructive by default** — existing files are left
alone. Pass `--force` only if the user explicitly asks to overwrite.

`owl init` materializes (from the repo-root seeds in this repository):

- `.owl/config.yaml` with default storage roles
- `.owl/workflows.yaml` — workflow registry (`feature`, `composite_feature` enabled by default)
- `.owl/artifacts.yaml` — artifact-type registry
- `.owl/workflows/feature/` and `.owl/workflows/composite_feature/`
  (workflow YAML + per-step `.context.md` files + brief variants)
- `.owl/artifacts/<type>/` for `brief`, `design`, `plan`, `review`,
  `verification`, `decomposition` (each with `artifact.yaml` and
  default Markdown templates)
- `.owl/overlays/<step>.md` — one overlay per step id (`brief`, `design`,
  `plan`, `implement`, `review_code`, `merge_docs`, `archive`, `commit_push`)
- `tasks/index.yaml` — empty task index
- `docs/.keep` — placeholder so the storage role exists
- `.claude/skills/owl-cli/SKILL.md`
- `.claude/skills/owl-step-run/SKILL.md`
- `.claude/skills/owl-orchestrator/SKILL.md`
- `.claude/skills/owl-init/SKILL.md`
- `.claude/skills/owl-author/SKILL.md`
- `.claude/skills/_owl_conventions.md` — shared conventions referenced by the skills above
- `.claude/commands/owl-cli.md`
- `.claude/commands/owl-init.md`
- `.claude/commands/owl-orchestrator.md`
- `.claude/commands/owl-step-run.md`
- `.claude/commands/owl-author.md`
- `.claude/commands/owl-task-create.md`
- `.claude/commands/owl-task-status.md`
- `.claude/commands/owl-task-next.md`
- `.claude/commands/owl-workflow-show.md`

### 4. Update the target project's `.gitignore`

Add these entries so per-clone pointer files and transient
archive-staging dirs do not get committed:

```
# Owl local state (per-clone pointer files, not shared)
.owl/local/

# Owl atomic-archive staging (per-transaction work dirs; transient)
tasks/.archive-staging/
```

### 5. Required Owl skills (must be present in `.claude/skills/`)

| Skill              | Layer        | Role                                                                       |
| ------------------ | ------------ | -------------------------------------------------------------------------- |
| `owl-cli`          | CLI wrapper  | Canonical interface to `bin/owl` — used by every other Owl skill.          |
| `owl-step-run`     | Executor     | Runs any ready step from the `owl step show` bundle.                       |
| `owl-orchestrator` | Coordinator  | Picks the next ready step and delegates execution.                         |
| `owl-init`         | Bootstrap    | One-shot wizard that fills `.owl/config.yaml` `settings:` via Q&A + CLI.   |
| `owl-author`       | Authoring    | Q&A skill that creates / edits workflow + artifact-type definitions.       |

`owl init` installs all five from the seeds. After running it, verify:

```bash
ls .claude/skills/owl-cli/SKILL.md \
   .claude/skills/owl-step-run/SKILL.md \
   .claude/skills/owl-orchestrator/SKILL.md \
   .claude/skills/owl-init/SKILL.md \
   .claude/skills/owl-author/SKILL.md
```

If any file is missing, re-run `owl init --force` or copy from
`skills/<name>/SKILL.md` in this repository by hand. **Do not invent
SKILL.md content** — the seeded versions are the contract.

### 6. Configure runtime settings (optional)

`owl init` already seeded a working `.owl/config.yaml` with sensible
defaults — communication language `en`, filesystem storage, both
seeded workflows enabled. **The agent does not need to run the wizard
to start working.** Skip directly to step 7 if the user has not asked
for customization.

Run the wizard when the user wants to change language, storage role
paths, or filter the enabled-workflow list. The wizard is a **skill
the agent invokes itself** — it is *not* a command the user must type:

```
agent → Skill(skill: "owl-init")        # or, equivalently, /owl-init
        ↓
        wizard runs `AskUserQuestion`   # user answers in the chat
        ↓
        wizard runs `owl config set settings.* …` for each answer
        ↓
        wizard runs `owl config validate --json` and prints a summary
```

The wizard speaks English until `settings.language.communication` is
recorded, then switches to that language. It asks for:

1. communication language (required)
2. artifact language (default = communication)
3. docs language (default = communication)
4. storage backend (`filesystem` in v1)
5. storage role paths (accept defaults or per-role override)
6. enabled workflows (multi-select; empty list = allow all)

Every answer is persisted via `owl config set settings.* VALUE`. The
`settings.workflows.enabled` key is an *optional filter* — an empty
list (the seeded default) means **all registered workflows are
allowed**, not "no workflows". The actual workflow registration lives
in `.owl/workflows.yaml` (seeded by `owl init`); `owl workflow list
--json` is the authoritative check.

### 7. Validate the install

```bash
owl config validate --json     # → {ok: true, errors: []}
owl workflow list --json       # → at least `feature` and `composite_feature`
owl artifact-type list --json  # → brief, design, plan, review, verification, decomposition
```

If any of these returns `ok: false` or an empty list, stop and ask
the user — do not "fix" it by editing `.owl/` files directly.

### 8. Finish setup: confirm with the user and create the first task

At this point the install is complete and Owl is fully operational.
The agent finishes by checking with the user one of two ways:

- **The user has already named a task** ("set up Owl and start working
  on X"): create the task directly and hand it to the orchestrator.

  ```bash
  owl task create --workflow feature --title "<X>" --json
  # → then invoke the orchestrator skill yourself: Skill(skill: "owl-orchestrator")
  ```

- **The user only asked to install Owl**: confirm install completion
  in one sentence, list the seeded workflows (`owl workflow list
  --json`), and ask the user — via `AskUserQuestion` — what the first
  task should be. Do not stop with "now you must type `/owl-task-create`";
  the agent itself creates the task once the user answers.

  Equivalent skill-level entry point: `Skill(skill: "owl-task-create")`
  (slash-command handle: `/owl-task-create feature "..."`).

The general rule for an agent installing Owl: every `/owl-*` slash
command in this README is a handle for a skill **the agent can invoke
itself** through the `Skill` tool. User interaction inside a skill
happens through `AskUserQuestion`, not by waiting for the user to
type the slash command. Do not end an install with "the rest is
manual" — finish setup yourself, ask the user only for the product
decisions the wizard / first-task creation actually require.

### 9. Project-level invariants the agent must respect

- **`bin/owl` is the only interface.** Never `cat` / `grep` / `find`
  through `.owl/`, `tasks/`, or `docs/`. If a command you need is
  missing from `owl --help`, stop and report — do not invent flags.
- **Use `--json` for every read.** JSON shapes are the stable
  contract; human-readable output is not.
- **Workflow YAML and artifact templates are edited through
  `owl-author`**, not by direct file edits.
- **Settings are edited through `owl config set settings.<path>`**,
  not by editing `.owl/config.yaml` by hand.
- **Composite archives are atomic.** When `owl archive PARENT-ID`
  returns `composite_with_unready_children`, do not "force" anything
  — surface the missing child steps to the user.
- **Skills follow Owl skill conventions** (see
  `skills/_owl_conventions.md` in this repo): numbered Q&A prompts,
  autonomous-by-default execution, stop conditions surfaced as a
  single explicit question.

## Authoring new workflows

The fastest path is the agent-driven `/owl-author` slash command — it
walks you through three modes (create workflow, create artifact-type,
edit existing) via Q&A and persists every change through
`owl workflow ...` / `owl artifact-type ...` (no direct YAML editing).

To scaffold by hand:

```bash
owl workflow new --id my_workflow --kind task --json
owl artifact-type new --id my_artifact --json
owl workflow validate my_workflow --json
```

Then drop the per-step `.context.md` files next to the generated
`workflow.yaml`, and the workflow will appear in `owl workflow list`
without a restart.

## Testing

```bash
bundle exec rspec
bundle exec rubocop
```

Do **not** run `rubocop -A` — `Style/StringConcatenation` autocorrect
rewrites `Pathname + String` into broken string interpolation. The cop
is disabled in `.rubocop.yml`, but `-A` would silently re-enable it.

## Repository layout

```
.
├── owl-cli.gemspec               # gem packaging (name: owl-cli, executable: owl)
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
├── CLAUDE.md                     # KOS bootstrap entrypoint (for Owl's own development)
├── AGENTS.md / ARCHITECTURE.md / REQUIREMENTS.md / IMPLEMENTATION_PLAN.md
│                                 # historical fallback — see CLAUDE.md
└── README.md                     # this file
```

> Do not confuse repo-root `skills/` (Owl defaults, the seed that
> Owl ships into target projects) with `.claude/skills/kos-*` (KOS
> skills used while *developing* Owl itself — a separate concept).

## KOS integration (Owl's own development)

This repository is itself connected to KOS — the authoritative source
of agent workflow state used to develop Owl. See `CLAUDE.md` for the
KOS bootstrap, the installed `kos-*` slash commands, and the runtime
endpoint. Projects that *use* Owl do not need KOS.
