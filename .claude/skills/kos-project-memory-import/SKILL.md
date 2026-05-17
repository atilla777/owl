---
name: kos-project-memory-import
description: Migrate durable repository agent memory into KOS knowledge before switching to KOS workflow state.
---

# Skill: kos-project-memory-import

## Purpose

`kos-project-memory-import` migrates repository Markdown files that define agent-facing project memory into KOS knowledge articles.

Use it during KOS setup for an existing project so later KOS skills can load rules, workflow guidance, invariants, and project conventions through the KOS API instead of treating local Markdown files as the active source of truth.

## When To Use

Use this skill when a project is being connected to KOS and already has local agent memory files, such as:

- `AGENTS.md`
- `CLAUDE.md`, `GEMINI.md`, or similar runtime instruction files
- `README.md` sections that instruct agents how to use KOS
- `agents/rules/*.md`
- `agents/skills/*.md`
- task-independent architecture, workflow, or convention documents linked from those files

Do not use this skill for task-local specifications, transient implementation plans, generated logs, private notes, secrets, or human-facing README content that is not durable agent operating context.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- When work uncovers a repeatable project-specific pitfall, API behavior, workflow gotcha, verification issue, or other lesson that would prevent future mistakes, treat it as durable knowledge rather than private memory.
- Classify these entries with taxonomy `kind: nuance` and select existing `scope` and `topic` tags from `kos-api.list_tags`; do not invent taxonomy tags or free-form "what I learned" labels.
- Stage skills should return durable nuance candidates to the orchestrator. The orchestrator persists them through `kos-api.check_knowledge_conflicts` followed by `create_knowledge_entry` or `update_knowledge_entry` when the knowledge is not already captured.

- Use `kos-api` for project resolution, taxonomy lookup, conflict checks, knowledge creation, knowledge updates, search, and context verification.
- Use `kos-repo` rules for safe repository edits when switching the project entrypoint to KOS.
- Treat KOS knowledge articles as authoritative only after import and API verification succeed.
- Keep the original Markdown files intact until the final switch-over phase.
- Replace only the primary agent entrypoint by default, usually `AGENTS.md`; do not rewrite `README.md` or every migrated Markdown file unless the human explicitly asks for that broader cleanup.
- The KOS repository `skills/kos-*` directories are the install source for runtime KOS skills. A target project should receive copied skills in its runtime directory, not wrappers that point back to a machine-local KOS checkout.
- For OpenCode targets, configure `kos-standard-agent` and `kos-advanced-agent` in `opencode.json` during installation; do not rely on `general` for all KOS slash commands.

## Inputs

- repository root path
- optional project id or project slug; default to the current repository project through `kos-api.resolve_or_create_current_project`
- optional actor user id for mutating KOS API calls
- primary entrypoint path, defaulting to `AGENTS.md`
- optional additional seed paths for project-specific instruction files
- optional dry-run flag; default should be dry-run unless the caller explicitly requests mutation

## Outputs

- discovered candidate Markdown files
- imported, updated, skipped, and blocked file lists
- created or updated KOS knowledge article ids
- retrieval verification summary for imported knowledge
- switch-over summary when `AGENTS.md` was replaced
- explicit stop reason and required human decision when migration cannot continue safely

## Migration Scope

Start discovery from the primary entrypoint and known project-memory paths:

- the pre-migration primary entrypoint, usually the original `AGENTS.md` before switch-over
- runtime instruction files with names like `CLAUDE.md`, `GEMINI.md`, and `.cursor/rules/*.md` when present
- `README.md` only when it contains durable agent-facing rules for the target project itself, not general KOS product documentation or bootstrap API docs
- `agents/rules/*.md`
- `agents/skills/*.md`
- other repository-relative Markdown files linked from the discovered project-memory files

Include a file only when it contains durable agent operating context, for example:

- engineering rules
- workflow rules
- architecture invariants
- durable technical nuances
- reusable agent skill instructions
- project setup instructions for KOS
- source-of-truth ordering and context-loading policy

Skip files that are task-local, historical, generated, or unsafe to import, for example:

- `agents/specs/*.md` unless the human explicitly asks to migrate historical task specs
- post-migration bootstrap entrypoints whose only job is to tell agents to load KOS skills and retrieve KOS knowledge
- README sections that document KOS as a product rather than durable operating memory for the target project
- `CHANGELOG.md`
- generated API docs
- vendored dependency docs
- files under `tmp/`, `log/`, `storage/`, or build output directories
- files that appear to contain secrets, credentials, tokens, or private environment values

## Article Shape

KOS knowledge identity is taxonomy-based. Each article must have exactly one identity tag from the `kind`, `scope`, and `topic` groups, and KOS enforces one active article per identity inside a project or shared scope.

Because of that invariant, do not assume one imported source file can always become one KOS article. The default import unit is one article per stable taxonomy identity bucket, with one or more source files preserved inside that article.

Prefer stable titles that describe the imported memory bucket and include representative source paths:

```text
Project workflow rules: agents/rules/development_workflow.md
Project testing rules: agents/rules/testing_strategy.md
Project skill contracts: agents/skills/kos_workflow.md
```

Each article body should preserve each source Markdown section and add a short provenance header:

```markdown
Imported sources:

- `AGENTS.md`
- `agents/rules/development_workflow.md`

Imported by: `kos-project-memory-import`
Migration role: project workflow memory before KOS switch-over

---

## Source: `AGENTS.md` before KOS switch-over

<original AGENTS.md markdown>

---

## Source: `agents/rules/development_workflow.md`

<original rule markdown>
```

Each summary should explain the durable role of the imported memory bucket in one or two sentences.

Do not create an article for the replacement `AGENTS.md` generated during switch-over. That file is a local KOS entrypoint, not project knowledge. Its job is to tell the agent to use installed KOS skills, load the taxonomy dictionary, and retrieve context from KOS articles for normal work.

Do create or update a separate required project bootstrap article from durable pre-switch-over entrypoint rules and project-level operating requirements. This article is the Project Constitution: the expanded KOS-native main law of the project that every agent must load before normal work. It must use `load_policy: required` with `required_project_bootstrap: true` so it is returned before ordinary relevance-based knowledge.

The Project Constitution must not duplicate the thin replacement `AGENTS.md`. `AGENTS.md` is only the runtime entrypoint that tells a stateless agent to load KOS skills and retrieve KOS knowledge. The constitution should instead expand durable project intent into a stable operating law: purpose, product direction, source-of-truth hierarchy, required workflow, quality gates, architecture/test expectations, knowledge-capture duties, repository handoff policy, and stop conditions. When older `AGENTS.md` content contains obsolete file-order workflow rules, preserve the durable intent but rewrite it around KOS API task/work-package state and required knowledge retrieval.

Create a separate article for a single source file only when its selected `kind`, `scope`, and `topic` identity will be unique among active KOS articles for the project. When multiple files naturally share the same identity, merge them into one article rather than fighting the KOS identity invariant.

## Taxonomy Guidance

Before creating articles, load the tag dictionary with `kos-api.list_tags`. Select existing tags instead of creating taxonomy records in this skill.

KOS ships a system-defined identity taxonomy. Treat these tag groups as canonical and require them before import:

- `kind` defines what kind of knowledge the article stores. Use exactly one tag such as `rule`, `decision`, `nuance`, or `invariant`.
- `scope` defines where the knowledge applies, such as `agent`, `rails`, `api`, `database`, `frontend`, `project_local`, or `shared`.
- `topic` defines the subject agents should use when retrieving the article, such as `workflow`, `testing`, `taxonomy`, `retrieval`, `ui`, or `service`.

Each system-defined group and tag must include a human-readable description. Use those descriptions as the primary guidance for choosing tags and for deciding which tags to search by when verifying imported knowledge.

Run a taxonomy preflight before classifying files:

- confirm the `kind`, `scope`, and `topic` groups exist
- confirm those groups have `system_defined: true`
- confirm each group has a non-empty description
- confirm the needed system tags exist, have `system_defined: true`, and have non-empty descriptions
- stop and ask for a setup fix when the system taxonomy is missing, user-defined, or undescribed

Prefer tags that express:

- knowledge type through `kind`: rule, decision, invariant, or nuance
- subject area through `topic`: workflow, retrieval, testing, taxonomy, service, or UI
- execution surface through `scope`: agent, API, Rails, database, frontend, project-local, or shared

Stop and ask for a taxonomy decision when no available tags can represent imported project-memory articles well enough for retrieval.

Do not collapse unrelated source files into one article just because the tags are available. Split imported memory into stable retrieval buckets first, then assign identity tags. Good buckets include workflow rules, architecture rules, testing rules, taxonomy policy, skill contracts, and the Project Constitution article. Do not use a bootstrap/API bucket for the replacement `AGENTS.md`; bootstrap belongs in the local entrypoint and KOS runtime skills, while durable pre-switch-over entrypoint rules belong in the Project Constitution article. Merge multiple files only when they naturally share the same `kind`, `scope`, and `topic` identity.

## API Import Workflow

1. Resolve actor identity and project context through `kos-api`.
2. Confirm runtime KOS skills are installed in the target project before replacing the primary agent entrypoint. For OpenCode, this means copied `skills/kos-*` directories exist under `.opencode/skills/`, matching `.opencode/commands/kos-*.md` files exist, `opencode.json` allows `kos-*` skills, and KOS subagents are configured.
3. If runtime skills are missing and the KOS repository path is available, copy the KOS repository `skills/kos-*` directories into the target runtime skill directory and create matching command files. Do not create thin wrappers to the KOS checkout for normal project installation.
4. For OpenCode, configure `opencode.json` with `kos-standard-agent` on the cheaper standard model for routine KOS API/CLI, verification, repository, git handoff, and completion-report work, plus `kos-advanced-agent` on the advanced model for orchestration, brainstorming, planning, implementation, review, and memory import work. Slash command frontmatter should route each `kos-*` command to the matching agent tier.
5. Discover candidate Markdown files from the primary entrypoint, known memory paths, and repository-relative Markdown links.
6. Classify each candidate as importable, skipped, or blocked.
7. Load available tags through `kos-api.list_tags` and run the taxonomy preflight described above.
8. Split importable files into stable retrieval buckets and choose one `kind`, one `scope`, and one `topic` tag for each bucket using the group and tag descriptions.
9. Group importable files by the selected taxonomy identity before calling write APIs.
10. For each import bucket, call `kos-api.check_knowledge_conflicts(project_id, tag_ids:)`.
11. If an existing article clearly represents the same taxonomy identity and migration role, merge the imported sources into that article through `kos-api.update_knowledge_entry` with the latest `lock_version`.
12. If no matching article exists, create it through `kos-api.create_knowledge_entry`.
13. Create or update the Project Constitution article from durable entrypoint/project-level rules using `load_policy: required` and `required_project_bootstrap: true`. Use existing taxonomy tags, normally `kind: rule`, `scope: agent` or `project_local`, and `topic: workflow` or `retrieval`, based on the tag descriptions. Its title should make the constitutional role obvious, for example `<Project name> Project Constitution`.
14. Record created and updated article ids plus source paths in the migration report, including the Project Constitution article id.
15. Verify imported articles through `kos-api.list_knowledge_entries` and targeted `kos-api.search` queries using source paths and workflow terms.
16. Verify stage retrieval through `kos-api.get_knowledge_context` when a task id and stage are available, and confirm the Project Constitution article appears in `bootstrap_articles`.
17. Continue to switch-over only after runtime skills are installed, import verification succeeds, the Project Constitution article is present, and OpenCode subagent routing is configured when OpenCode is the target runtime.

## Switch-Over Workflow

Switch-over changes the repository so future agents start from KOS instead of the old Markdown entrypoint.

By default, switch over only `AGENTS.md`.

1. Confirm the pre-migration primary entrypoint existed and any durable rules it contained were included in the successful import buckets or the Project Constitution article.
2. Confirm imported rule, decision, invariant, or nuance articles can be found through KOS API search using taxonomy tags selected from the tag dictionary descriptions.
3. Confirm the Project Constitution article exists with `load_policy: required` and `required_project_bootstrap: true`, and appears in `get_knowledge_context(...).knowledge_context.bootstrap_articles`.
4. Choose a backup path without overwriting an existing backup:
   - prefer `AGENTS_BKP.md`
   - if it exists, use `AGENTS_BKP_YYYYMMDD_HHMMSS.md`
5. Rename the old `AGENTS.md` to the backup path.
6. Create a new minimal `AGENTS.md` that points agents to KOS as the primary source of project memory.
7. Re-read the new `AGENTS.md` and verify it contains the KOS source-of-truth statement, normal-work instructions for installed KOS skills, and the fallback stop condition.
8. Report the backup path and the retrieval checks that justified the switch-over.

The replacement `AGENTS.md` must not be imported back into KOS as a knowledge article. It is intentionally a thin local KOS entrypoint so a stateless agent can load installed KOS skills and real project memory from tagged knowledge articles.

The replacement `AGENTS.md` should include this minimum content, adapted to the project:

```markdown
# Agent Instructions

This project uses KOS as the primary source of agent-facing project memory.

1. For normal work, load the installed KOS skills, especially `kos-api` and `kos-orchestrator`.
2. Resolve or create the current repository project in KOS.
3. Use KOS API task, work-package, and knowledge-context operations as the active source of workflow memory.
4. Load required project knowledge context from KOS before planning, implementation, verification, review, or git handoff; KOS bootstrap knowledge entries marked with `load_policy: required` are the AGENTS.md replacement path and must be treated as mandatory context.
5. If the runtime skill registry is unavailable but `.opencode/skills/kos-*` exists, read the installed KOS skill files as a fallback, report the missing runtime registration, and continue through KOS API state.
6. Treat local backup files such as `AGENTS_BKP.md` as historical fallback only, not as active source of truth.

If KOS is unavailable or imported project memory cannot be retrieved, stop and ask the human before continuing.
```

## Stop Conditions

Stop and ask the human for a decision when:

- KOS API is unavailable
- actor identity is missing for mutating API operations
- project identity cannot be resolved safely
- runtime KOS skills or commands cannot be installed or verified in the target project
- OpenCode is the target runtime but `kos-standard-agent`, `kos-advanced-agent`, or command frontmatter routing cannot be configured or verified
- candidate files include possible secrets or private machine-local data
- taxonomy tags are insufficient for retrievable project-memory articles
- conflict checks find an existing article with the same taxonomy identity that cannot be safely merged or updated
- import verification cannot find the migrated entrypoint through API search
- `AGENTS.md` has uncommitted user edits that were not part of the migration input
- a backup path would overwrite an existing file
- the caller asks to rewrite `README.md` or all migrated Markdown files without explicit scope confirmation

## Verification

Verify this skill by:

- dry-running discovery on a repository that has `AGENTS.md`, `agents/rules/*.md`, and linked Markdown files
- importing a small project-memory set into KOS and confirming `list_knowledge_entries` returns the created or merged articles
- confirming `search` can find imported articles by source path and workflow terms
- confirming `get_knowledge_context` returns imported project-memory articles for a relevant task and stage when available
- confirming switch-over does not run when API verification fails
- confirming switch-over does not run when runtime KOS skills or slash commands are missing
- confirming switch-over does not run for OpenCode when KOS subagent routing is missing
- confirming switch-over backs up only `AGENTS.md` by default and leaves `README.md` plus other migrated files untouched
- confirming an existing `AGENTS_BKP.md` causes a timestamped backup path rather than overwrite
