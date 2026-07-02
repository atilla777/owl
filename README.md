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
                       # → ready to use: workflows `feature`, `composite_feature`,
                       #   `hotfix`, `refactor`, and `quick` are all enabled;
                       #   default language is `en`.

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

- **Workflow-driven task lifecycle.** Five built-in workflows seeded and
  enabled by `owl init`: `feature` (default), `composite_feature`, `hotfix`
  (lean urgent fix — brief → implement → review_code → commit_push), `refactor`
  (full-ceremony refactoring flow), and `quick` (minimal autonomous
  brief → implement → commit_push). Each is a graph of typed steps. On top of
  the workflow choice, the `brief` step also has bug (`root_cause`) and refactor
  (`problem_inventory`) framing **variants**.
- **Declarative artifacts.** Every step declares which artifact(s) it
  produces; each artifact type has a Markdown template, a required-
  section list (each section `error` = blocking or `warning` =
  recommended), and frontmatter schema. Artifacts are validated on
  step completion.
- **Session-typed step model.** Every step declares `session_type:
  discussion | execution` ([RFC #1](docs/rfcs/0001-session-typed-steps.md) §2). Discussion steps run in the main
  agent session through `owl-step-discussion`; execution steps run in
  an isolated subagent session through `owl-step-execution` and emit a
  structured report via `owl step report --body -`. The per-step prompt
  lives in a `.context.md` file next to the workflow YAML; adding a new
  step = dropping a new Markdown file, no Ruby code.
- **Composite tasks.** A `composite_feature` decomposes into child
  tasks linked by `parent_id`; the parent tracks aggregate readiness
  and archives the whole subtree atomically.
- **Publishing pipeline.** A workflow can declare `publishes:` rules
  to copy approved artifacts from a task tree into `docs/`. On publish,
  an approved `design` is flipped to `shipped` (source + copy), and a
  generated `docs/README.md` index of published task docs is refreshed.
- **Pluggable storage.** Storage roles (`tasks`, `docs`, `archive`,
  `control`, `local_state`, `index`, `specs`) live in `.owl/config.yaml`;
  workflow YAML never hard-codes physical paths.
- **Upgrade-safe customization.** Owl-shipped workflows and artifact
  types are `managed: true` (read-only from the project side); you
  customize by cloning them to a project-owned copy (`--from`, `managed:
  false`). `owl self-update` updates the gem; `owl upgrade` then refreshes
  a project's copied seed files in place, preserving everything you own.
- **Full authoring via CLI.** Workflows, artifact types, their templates,
  step-context prompts, and registry entries are all created and edited
  through `owl workflow …` / `owl artifact-type …` — no hand-editing of
  `.owl/` files (see [Authoring](#authoring-new-workflows)).
- **Slash-command surface for agents.** `owl init`, `owl-task-create`,
  `owl-task-next`, `owl-orchestrator`, `owl-step-discussion`,
  `owl-step-execution`, `owl-author` are installed into `.claude/` so
  any Claude Code session in the project can drive Owl end-to-end.

## How it works

```
                ┌──────────────────┐
   user / LLM ──▶  /owl-* slash    │
                │  commands        │
                └────────┬─────────┘
                         ▼
                ┌──────────────────┐
                │  Owl skills      │  owl-orchestrator → owl-step-discussion
                │  (.claude/skills)│  (main session)  + owl-step-execution
                │                  │                    (subagent, via Task tool)
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

1. **Create a task** with a workflow key (`feature`, `composite_feature`,
   `hotfix`, `refactor`, `quick`) and a title — optionally choosing a
   `brief` variant.
2. **Ask the orchestrator** for the next ready step
   (`owl task ready-steps`).
3. **Execute the step.** `owl step show TASK-ID STEP-ID --json` returns
   a self-contained bundle — step config (including `title`, `session_type`,
   `model_tier`, normalized `optional`, and `variants_keys`) + the
   resolved per-step prompt + the artifact template + the task spec.
   The bound skill (`owl-step-discussion` for discussion-typed steps,
   `owl-step-execution` for execution-typed steps) follows the prompt
   and writes the artifact at the resolved path. Execution steps
   additionally emit a structured report through `owl step report
   --body -`.
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
| `.owl/config.yaml`                        | Control plane — storage role paths, language, enabled workflows, `context_overlays`, `owl.version` (materializing version). |
| `.owl/workflows.yaml`                     | Workflow registry — per entry `key → source path`, `enabled`, and `managed` (provenance: Owl-shipped vs project-owned). |
| `.owl/artifacts.yaml`                     | Artifact-type registry — per entry `key → source path` and `managed` (provenance). |
| `.owl/workflows/<id>/workflow.yaml`       | Declared workflow (steps, artifacts, publishes, variants).              |
| `.owl/workflows/<id>/<step>.context.md`   | Per-step prompt the universal executor follows.                         |
| `.owl/artifacts/<type>/artifact.yaml`     | Artifact-type definition (frontmatter schema, required sections).       |
| `.owl/artifacts/<type>/templates/*.md`    | Markdown templates for each artifact type.                              |
| `.owl/overlays/<step>.md`                 | Cross-workflow overlay merged into the step prompt (one per step id).   |
| `.owl/overlays/<step>/<variant>.md`       | Variant-specific overlay merged on top of `.owl/overlays/<step>.md`.    |
| `.owl/local/current.yaml`                 | "Current task" pointer (per-clone, not committed).                      |
| `.owl/.backup/<timestamp>/`               | Files replaced by `owl upgrade` (rollback copies; gitignored).          |
| `tasks/<TASK-ID>/task.yaml`               | Task state — workflow key, step statuses, variants, parent_id.          |
| `tasks/<TASK-ID>/{brief,design,plan,…}.md`| Active task artifacts.                                                  |
| `tasks/index.yaml`                        | Cached task index (rebuildable via `owl task index rebuild`).           |
| `tasks/archive/<date>-<TASK-ID>-<slug>/`  | Archived tasks (composite subtrees archived atomically).                |
| `docs/`                                   | Published task artifact copies + generated `README.md` index (`owl publish`). |
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
`step_invocation.json`, `step_report.json`,
`step_context_frontmatter.json`) are validated in-process — they
constrain what a workflow / artifact / step bundle is allowed to look
like. Because they live in the gem (never copied into a project), they
are always current and never need an `owl upgrade`.

### Session-typed step model

```yaml
# .owl/workflows/feature/workflow.yaml (excerpt)
steps:
  - id: brief
    skill: owl-step-discussion
    session_type: discussion        # main agent session, may ask user
    tier: advanced
    default_variant: feature
    variants:
      feature:           # collect requirements (default)
        context_file: brief.feature.context.md
      root_cause:        # bug-fix framing
        context_file: brief.root_cause.context.md
      problem_inventory: # refactor framing
        context_file: brief.problem_inventory.context.md
  - id: plan
    skill: owl-step-discussion
    session_type: discussion
    tier: advanced
    context_file: plan.context.md
    requires: [brief]
    creates: [plan]
  - id: implement
    skill: owl-step-execution
    session_type: execution         # subagent, no direct user prompt
    tier: advanced
    context_file: implement.context.md
    requires: [plan]
  - id: review_code
    skill: owl-step-execution
    session_type: execution
    tier: advanced
    verify: true
    context_file: review_code.context.md
    requires: [implement]
    creates: [review, verification]
```

`owl step show TASK-ID brief --json` returns a merged bundle (step
config + `title` + `session_type` + `model_tier` + normalized
`optional` + `variants_keys` + resolved `context` body + artifact
template + parent task spec). The same five contract fields appear
on every entry of `owl task ready-steps --json` so the orchestrator
can route steps without re-reading the workflow YAML. Note that the
JSON contract exposes the workflow YAML `tier:` key as `model_tier`.
The bound skill consumes that bundle and produces the declared artifact
at the path returned by `owl artifact resolve`. Execution steps
additionally write a structured report to
`.owl/local/reports/<TASK-ID>/<STEP-ID>.md` via `owl step report
--body -`; the orchestrator reads it back through `owl step report
--read`. Tier→model mapping is per-environment (`~/.config/owl/tier_map.yaml`
or `$OWL_TIER_MAP_PATH`) — see `docs/examples/tier_map.example.yaml`.

### Customizing step instructions (overlays)

A project adds its own instructions to a step *without* editing Owl-shipped
templates by dropping **overlay** Markdown next to the step. Overlays are
merged into the bundle the bound skill reads, on top of the workflow's
built-in `<step>.context.md`. There are three layers, applied in this order:

1. **Convention** (universal) — `.owl/overlays/<step>.md`, then
   `docs/ai/<step>.md`. Just create the file and write your text.
2. **Variant** (only when the task picks a variant) —
   `.owl/overlays/<step>/<variant>.md`, then `docs/ai/<step>/<variant>.md`.
3. **Config** (explicit paths) — `context_overlays.<step>` in
   `.owl/config.yaml`. Point a step at any number of existing files; handy for
   reusing one document across several steps. Relative paths resolve from the
   project root, absolute paths are used as-is.

```yaml
# .owl/config.yaml — top-level block, sibling to `settings:` / `storage:`
context_overlays:
  implement:
    - docs/agents/27_Owl_Ruby_code_architecture.md
    - docs/agents/29_Owl_Ruby_linting_RuboCop.md
  commit_push:
    - docs/ai/git-conventions.md
```

Behavior: empty files and HTML-comment-only stubs (the `owl init` seed) are
skipped, so a placeholder overlay never pollutes context until you add real
text; duplicate paths are de-duped; an overlay larger than 8 KB is still
merged but flagged `warning: too_long` for the step log. Rule of thumb: text
unique to one step → layer 1; an existing `docs/…` doc you want to reuse across
steps → layer 3.

Inspect overlay resolution directly with the `owl overlay` commands (handy
when an overlay "isn't applying"):

```bash
owl overlay list  <STEP-ID> [--variant V] --json   # every candidate path, found/missing, in order
owl overlay show  <STEP-ID> [--variant V] --json   # the bodies that actually apply
owl overlay validate <STEP-ID> [--variant V] --json # applied count + warnings (too_long, …)
```

The same merged array is also embedded in `owl step show <TASK-ID> <STEP-ID>
--json` under `overlays[]` (each `source` / `body` / `warning`).

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
# For the full discover→decompose→rollup refactor flow, see
# docs/recipes/refactor-discovery.md (composite_feature + problem_inventory).

# 3d. Or a big initiative that decomposes into child tasks
owl task create --workflow composite_feature \
  --title "Multi-tenant data isolation" --json

# 4. Drive the task end-to-end
/owl-orchestrator
# The orchestrator:
#   • reads `owl task ready-steps TASK-ID --json`
#   • picks the first ready step (e.g. `brief`)
#   • calls `owl step show TASK-ID brief --json` for the bundle
#   • dispatches by session_type: discussion → `owl-step-discussion`
#     in the main session; execution → `owl-step-execution` in a subagent
#   • the bound skill writes brief.md
#   • runs `owl artifact validate TASK-ID brief --json`
#   • runs `owl step complete TASK-ID brief`
#   • loops to the next step (design → plan → implement → review_code …)

# 5. Inspect progress at any time
owl status TASK-ID --json
# → { steps: [...], progress: {done, total, pct}, blockers: [...], children: [...] }

# 6. For composite tasks, walk the subtree
owl task tree TASK-ID --json
owl task aggregate-status PARENT-ID --json
owl task child create PARENT-ID --workflow feature \
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
owl workflow show ID --json                 # rendered ASCII / legacy JSON
owl overview [TASK-ID] --json               # ASCII task tree (hierarchy, status, deps, current)
owl workflow source show ID --json          # raw workflow.yaml body (round-trip edit)
owl workflow context show ID STEP --json    # a step's context-file body
owl artifact-type template show ID --json   # an artifact template body
owl overlay show STEP-ID --json             # overlays that apply to a step
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

owl --version                      # → owl <version>, e.g. owl 1.7.1
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
- `.owl/workflows.yaml` — workflow registry (`feature`, `composite_feature`,
  `hotfix`, `refactor`, `quick` — all enabled by default)
- `.owl/artifacts.yaml` — artifact-type registry
- `.owl/workflows/{feature,composite_feature,hotfix,refactor,quick}/`
  (workflow YAML + per-step `.context.md` files + brief variants)
- `.owl/artifacts/<type>/` for `brief`, `design`, `plan`, `review`,
  `verification`, `decomposition`, `spec`, `spec_delta` (each with
  `artifact.yaml` and default Markdown templates)
- `.owl/overlays/<step>.md` — one overlay per step id (`brief`, `design`,
  `plan`, `implement`, `review_code`, `merge_docs`, `archive`, `commit_push`,
  plus `orchestrator` for coordinator-level guidance)
- `tasks/index.yaml` — empty task index
- `docs/.keep` — placeholder so the storage role exists
- `.claude/skills/owl-cli/SKILL.md`
- `.claude/skills/owl-step-discussion/SKILL.md`
- `.claude/skills/owl-step-execution/SKILL.md`
- `.claude/skills/owl-orchestrator/SKILL.md`
- `.claude/skills/owl-init/SKILL.md`
- `.claude/skills/owl-author/SKILL.md`
- `.claude/skills/_owl_conventions.md` — shared conventions referenced by the skills above
- `.claude/commands/owl-cli.md`
- `.claude/commands/owl-init.md`
- `.claude/commands/owl-orchestrator.md`
- `.claude/commands/owl-step-discussion.md`
- `.claude/commands/owl-step-execution.md`
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

# Owl upgrade backups (rollback copies written by `owl upgrade`)
.owl/.backup/
```

### 5. Required Owl skills (must be present in `.claude/skills/`)

| Skill                  | Layer        | Role                                                                       |
| ---------------------- | ------------ | -------------------------------------------------------------------------- |
| `owl-cli`              | CLI wrapper  | Canonical interface to `bin/owl` — used by every other Owl skill.          |
| `owl-step-discussion`  | Executor     | Runs `session_type: discussion` steps in the main agent session.           |
| `owl-step-execution`   | Executor     | Runs `session_type: execution` steps in an isolated subagent session.      |
| `owl-orchestrator`     | Coordinator  | Picks the next ready step and dispatches by `session_type`.                |
| `owl-init`             | Bootstrap    | One-shot wizard that fills `.owl/config.yaml` `settings:` via Q&A + CLI.   |
| `owl-author`           | Authoring    | Q&A skill that creates / edits workflow + artifact-type definitions.       |

`owl init` installs all six from the seeds. After running it, verify:

```bash
ls .claude/skills/owl-cli/SKILL.md \
   .claude/skills/owl-step-discussion/SKILL.md \
   .claude/skills/owl-step-execution/SKILL.md \
   .claude/skills/owl-orchestrator/SKILL.md \
   .claude/skills/owl-init/SKILL.md \
   .claude/skills/owl-author/SKILL.md
```

If any file is missing, re-run `owl init --force` or copy from
`skills/<name>/SKILL.md` in this repository by hand. **Do not invent
SKILL.md content** — the seeded versions are the contract.

### 5b. Choosing the agent layout (Claude Code / OpenCode)

By default `owl init` materializes skills and commands into Claude
Code's layout (`.claude/skills/`, `.claude/commands/`). OpenCode uses
its own folders, so `owl init` takes an `--agent` flag to pick the
target layout:

```bash
owl init                      # .claude/  (default — Claude Code)
owl init --agent opencode     # .opencode/  (OpenCode only)
owl init --agent both         # both layouts
```

| `--agent`  | Skills materialized to | Commands materialized to |
| ---------- | ---------------------- | ------------------------ |
| `claude`   | `.claude/skills/`      | `.claude/commands/`      |
| `opencode` | `.opencode/skills/`    | `.opencode/commands/`    |
| `both`     | both of the above      | both of the above        |

The choice is persisted to `.owl/config.yaml` under
`settings.agent_targets`, so a later `owl init --force` re-materializes
into the same layout without re-passing `--agent`.

**Why a flag and not the `.claude/` defaults.** OpenCode *can* read
`.claude/skills/<name>/SKILL.md` natively, but its Claude-compatibility
can be turned off, and it never reads `.claude/commands/` (custom
commands only live under `.opencode/commands/`). `--agent opencode`
sidesteps both issues by writing OpenCode's own layout directly.

**Agent installing Owl: ask first.** When you don't already know which
harness will drive the project, ask the user via `AskUserQuestion`
("Claude Code, OpenCode, or both?") *before* running `owl init`, then
pass the matching `--agent` value. This is the same "agent asks, then
calls the CLI" pattern used throughout this README.

Verify the chosen layout, e.g. for OpenCode:

```bash
ls .opencode/skills/owl-orchestrator/SKILL.md
ls .opencode/commands/owl-orchestrator.md
```

Then `/owl-orchestrator`, `/owl-task-create`, etc. work in the OpenCode
TUI exactly as they do in Claude Code. Decide per project whether to
commit `.opencode/` or add it to `.gitignore` (step 4).

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
owl workflow list --json       # → feature, composite_feature, hotfix, refactor, quick
owl artifact-type list --json  # → brief, design, plan, review, verification, decomposition, spec, spec_delta
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
- **Workflow / artifact-type definitions, templates, and step-context
  prompts are edited through the CLI** — `owl-author` or the underlying
  `owl workflow …` / `owl artifact-type …` commands (`template set`,
  `context set`, `register`, …) — never by direct file edits. Owl-shipped
  (`managed: true`) definitions are read-only; clone with `--from` to
  customize.
- **Settings are edited through `owl config set settings.<path>`**,
  not by editing `.owl/config.yaml` by hand.
- **Composite archives are atomic.** When `owl archive PARENT-ID`
  returns `workflow_incomplete`, do not "force" anything
  — surface the missing steps (`details.incomplete_steps`) to the user.
- **Skills follow Owl skill conventions** (see
  `skills/_owl_conventions.md` in this repo): numbered Q&A prompts,
  autonomous-by-default execution, stop conditions surfaced as a
  single explicit question.

## Updating Owl

Owl content is split in two: the **gem** (`owl-cli` — CLI code, plus the
seed files) and each **project's copies** of those seeds, materialized
into `.owl/` and `.claude/` at `owl init`. Because the copies are
per-project, a gem update does not reach them — you refresh each project
explicitly. Two commands, two scopes:

```bash
owl self-update            # update the gem itself from github main (global, once)
owl self-update --check    # compare installed version with main, don't install
owl upgrade                # refresh THIS project's copied seed files (run per project)
owl upgrade --dry-run      # show what would change without writing
```

`owl self-update` clones `main`, builds the gemspec, and `gem install`s
the result (a git URL can't be `gem install`ed directly). Under a managed
Ruby or Bundler it may need `sudo` / a manual `bundle update`; it reports
the exact failure if so.

`owl upgrade` is **provenance-aware** — it only touches Owl-owned content
and never your customizations:

| Refreshed (Owl-owned) | Preserved (project-owned) |
| --------------------- | ------------------------- |
| `.claude`/`.opencode` skills + commands (`owl-*`) | `.owl/overlays/*`, `tasks/**` |
| Seed files of `managed: true` workflows / artifact types | Seed files of `managed: false` clones |
| `.owl/workflows.yaml` / `.owl/artifacts.yaml` (managed entries merged in) | Your `managed: false` registry entries + `default_workflow` |
| — | `.owl/config.yaml` (only `owl.version` is stamped) |

Replaced files are first copied to `.owl/.backup/<timestamp>/` (skip with
`--no-backup`). JSON schemas need no refresh — they live in the gem and
are read in-process. The version that materialized a project is recorded
in `.owl/config.yaml` (`owl.version`); `owl upgrade` reports the
`from → to` jump.

The clean update flow for several projects:

```bash
owl self-update                 # 1. bump the gem once
cd /path/to/project-a && owl upgrade   # 2. refresh each project
cd /path/to/project-b && owl upgrade
```

## Authoring new workflows

The fastest path is the agent-driven `/owl-author` slash command — it
walks you through three modes (create workflow, create artifact-type,
edit existing) via Q&A and persists every change through
`owl workflow ...` / `owl artifact-type ...` (no direct YAML editing).

Everything `owl-author` does is also available as plain CLI, so an
artifact type or workflow can be created and fully filled in without
touching `.owl/` by hand.

### Artifact types

```bash
# Create (optionally cloning an existing type) and register it.
owl artifact-type new --id my_plan --from plan --register --json
#   --from <id>   clone another type's definition + template
#   --register    add to .owl/artifacts.yaml as project-owned (managed: false)

# Read / write / validate the template body (use --template NAME for variants).
owl artifact-type template show     my_plan --json
owl artifact-type template set      my_plan --body - < template.md
owl artifact-type template validate my_plan --json

owl artifact-type validate   my_plan --json     # validate the definition shape
owl artifact-type register   my_plan            # register an existing definition
owl artifact-type unregister my_plan            # remove from the registry (files kept)
```

`template set` refuses Owl-shipped (`managed: true`) types — clone first
with `--from`, then edit the copy. This keeps your customizations
upgrade-safe (see [Updating Owl](#updating-owl)).

### Workflows

```bash
owl workflow new --id my_flow --kind task --from feature --register --json
owl workflow source  show my_flow --json                 # raw workflow.yaml for round-trip edits
owl workflow context show my_flow brief --variant feature --json
owl workflow context set  my_flow brief --body - < brief.context.md
owl workflow validate my_flow --json
owl workflow register   my_flow --enabled true
owl workflow unregister my_flow
```

A full rewrite round-trips through `owl workflow source show ID` →
edit → `owl workflow new --id ID --body - --force`. The workflow
appears in `owl workflow list` immediately, no restart.

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
│   ├── context/                  # step-context overlay resolution
│   ├── upgrade/                  # owl self-update (gem) + owl upgrade (project refresh)
│   ├── instructions/             # next-step packaging
│   └── validation/               # artifact validation
├── spec/owl/...                  # RSpec
├── CLAUDE.md                     # KOS bootstrap entrypoint (for Owl's own development)
├── AGENTS.md / ARCHITECTURE.md / REQUIREMENTS.md
│                                 # historical fallback — see CLAUDE.md
├── docs/historical/2026-05-implementation-plan.md
│                                 # archived IMPLEMENTATION_PLAN snapshot — current roadmap lives in KOS
└── README.md                     # this file
```

> Do not confuse repo-root `skills/` (Owl defaults, the seed that
> Owl ships into target projects) with `.claude/skills/kos-*` (KOS
> skills used while *developing* Owl itself — a separate concept).

## RFCs

Architectural decisions and contracts that need a normative reference
live in [`docs/rfcs/`](docs/rfcs/README.md). Each RFC is a versioned
document with `Draft → Accepted → Superseded` status; load-bearing
sections referenced from code carry **Implementation anchors** that
point at `lib/owl/...:N`.

| #    | Title                                                                    | Status   |
| ---- | ------------------------------------------------------------------------ | -------- |
| 0001 | [Session-typed steps and subagent contract](docs/rfcs/0001-session-typed-steps.md) | Accepted |

## KOS integration (Owl's own development)

This repository is itself connected to KOS — the authoritative source
of agent workflow state used to develop Owl. See `CLAUDE.md` for the
KOS bootstrap, the installed `kos-*` slash commands, and the runtime
endpoint. Projects that *use* Owl do not need KOS.
