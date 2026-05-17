---
name: kos-api
description: Use KOS API operations through the application skill contract.
---

# Skill: kos-api

## Purpose

`kos-api` is the shared technical skill for calling the KOS application API from other KOS-owned skills.

Use it to keep the orchestrator focused on workflow-state decisions and stage skills focused on their scoped work instead of rebuilding HTTP paths, request payloads, identity headers, lock-version handling, and artifact conventions.

## When To Use

Use this skill when another skill needs to:

- resolve or inspect projects
- list, create, claim, load, or update tasks
- load a task work package
- transition task workflow state
- read or write task agent artifacts
- update task specs through the API
- record final git delivery trace
- record compact orchestration run traces in task history
- retrieve taxonomy and knowledge context
- check, create, update, or delete knowledge articles
- read project, task, or knowledge history

Do not use this skill to decide product workflow stages, task scope, implementation plans, git handoff policy, or whether to persist a workflow mutation. Workflow-state decisions and persistence choices belong to the orchestrator; stage-specific work judgments belong to the relevant stage skill.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- When work uncovers a repeatable project-specific pitfall, API behavior, workflow gotcha, verification issue, or other lesson that would prevent future mistakes, treat it as durable knowledge rather than private memory.
- Classify these entries with taxonomy `kind: nuance` and select existing `scope` and `topic` tags from `kos-api.list_tags`; do not invent closed-vocabulary tags (`kind`, `scope`, `topic`) or free-form "what I learned" labels. The `subtopic` group is the only open-vocabulary dimension — pass `subtopic:` (string) to `create_knowledge_entry` / `update_knowledge_entry` to mint or attach a subtopic value at write time.
- Stage skills should return durable nuance candidates to the orchestrator. The orchestrator persists them through `kos-api.check_knowledge_conflicts` followed by `create_knowledge_entry` or `update_knowledge_entry` when the knowledge is not already captured.

- Prefer `lib/kos/client.rb` for HTTP mechanics and canonical operation names.
- Prefer `bin/kos` for routine agent-facing KOS API calls from skills and subagents. Use direct Ruby with `Kos::Client` only when the CLI does not yet expose the needed operation or when testing client internals.
- Treat the command list in this skill as the normal CLI contract for agent workflows. Prefer the documented commands below during routine execution, and use CLI discovery such as `bin/kos --help` only when troubleshooting or checking a command that is missing from the skill.
- Prefer the high-level task work package endpoint before assembling task context manually.
- Treat KOS API responses as authoritative. Do not rely on hidden local files or private skill state for resumable workflow data.
- Keep this skill in `skills/kos-api/` while it is experimental. Do not move it into `.opencode/skills` until the application skill workflow has been proven end to end.

## Inputs

- `KOS_BASE_URL`, defaulting to `http://127.0.0.1:3000` through `Kos::Client`
- optional actor user id for mutating requests
- optional project id or project slug; when omitted, resolve the current repository project through `Kos::Client#resolve_or_create_current_project`
- task id where task-scoped operations are needed
- lock version when updating lock-protected records
- artifact public type key, such as `development_plan`, `review_report`, or `completion_report`
- taxonomy tag ids for knowledge identity, retrieval, and conflict checks

## Outputs

- parsed JSON response from the KOS API
- clear API error message when the request fails
- no hidden persisted state outside the KOS application

## CLI Usage

Use `bin/kos` as the standard command-line wrapper for common KOS API operations. It prints JSON responses, reads `KOS_BASE_URL` and `KOS_USER_ID` through `Kos::Client`, exits non-zero on invalid usage or API errors, and keeps routine API access concise enough for cheaper standard-model subagents when the runtime supports model selection.

By default `bin/kos` talks to the KOS Rails server over HTTP. Setting `KOS_TRANSPORT=direct` switches `Kos::Client` to an in-process transport that loads the Rails environment and calls services/queries/presenters directly, so local scripts work without a running Rails server. The response JSON shape is identical to the HTTP transport. Direct mode pays ~1–2s boot at first use; HTTP remains the default and the CLI contract is unchanged.

Routine KOS CLI reads and simple KOS CLI writes should be delegated to `kos-standard-agent`, the lower-cost standard-model subagent configured in `opencode.json`, when this skill is used from an orchestrated workflow. Delegation is mechanical: the caller must provide the intended operation and current inputs, and the subagent returns the parsed result or error without choosing task selection, workflow transitions, artifact persistence, or conflict handling. The primary coding model remains responsible for deciding task scope, workflow transitions, implementation strategy, review judgment, and any ambiguous or high-risk mutation. If the runtime does not expose `kos-standard-agent` in the active session, run the documented CLI command directly and report that delegation was unavailable instead of inventing a subagent.

The commands below are the known agent-facing commands for this skill. Do not call CLI help during normal workflows. If a needed operation is not listed here, use the matching `Kos::Client` method when it is explicitly listed under Canonical Operations; otherwise stop and report the missing CLI contract.

Representative commands:

- `bin/kos projects:list`
- `bin/kos project:get PROJECT_ID`
- `bin/kos project:resolve PROJECT_SLUG [PROJECT_NAME]`
- `bin/kos project:resolve-current`
- `bin/kos tasks:list PROJECT_ID`
- `bin/kos task:get PROJECT_ID TASK_ID`
- `bin/kos task:claim-next PROJECT_ID [--mode MODE]`
- `bin/kos task:work-package PROJECT_ID TASK_ID`
- `bin/kos task:create PROJECT_ID TITLE BODY [--status STATUS] [--workflow-status STATUS] [--summary SUMMARY] [--body-file PATH] [--parent-id ID] [--task-role ROLE] [--priority N] [--task-type-id ID] [--agent-workflow-type-id ID]`
- `bin/kos task:spec:write PROJECT_ID TASK_ID LOCK_VERSION BODY|-`
- `bin/kos task:workflow:transition PROJECT_ID TASK_ID WORKFLOW_STATUS LOCK_VERSION`
- `bin/kos task:git-trace:finalize PROJECT_ID TASK_ID GIT_BRANCH GIT_COMMIT_SHA GIT_COMMIT_MESSAGE GIT_COMMIT_OBSERVED_AT LOCK_VERSION`
- `bin/kos task:git-handoff:no-op PROJECT_ID TASK_ID NO_OP_REASON LOCK_VERSION`
- `bin/kos task:orchestration-run:record PROJECT_ID TASK_ID BODY|- [--body-file PATH]`
- `bin/kos task:history PROJECT_ID TASK_ID`
- `bin/kos artifact:write PROJECT_ID TASK_ID development_plan -`
- `bin/kos artifact:write PROJECT_ID TASK_ID ARTIFACT_TYPE BODY|- [--lock-version LOCK_VERSION]`
- `bin/kos artifact:list PROJECT_ID TASK_ID`
- `bin/kos artifact:get PROJECT_ID TASK_ID ARTIFACT_TYPE`
- `bin/kos knowledge:context PROJECT_ID [--task-id TASK_ID] [--stage STAGE] [--skill SKILL] [--limit LIMIT] [--subtopic VALUE]`
- `bin/kos knowledge:tags PROJECT_ID`
- `bin/kos knowledge:entries:list PROJECT_ID`
- `bin/kos knowledge:entry:get PROJECT_ID ENTRY_ID`
- `bin/kos knowledge:entry:history PROJECT_ID ENTRY_ID`
- `bin/kos project:history PROJECT_ID`
- `bin/kos search PROJECT_ID QUERY [--tag-ids ID,ID]`

The command list above is intentionally explicit so agents do not need CLI discovery for normal KOS workflows.

### Response Shape Notes

A few endpoints return shapes that have surprised agents in the past — always iterate the actual structure rather than guessing top-level keys:

- `tasks:list` returns a **tree**: each entry has `children: [...]` nested recursively. The top-level `.tasks[]` only contains root tasks (those with no parent). To walk every task, use jq recursive descent (`.. | objects | select(.id)`) or follow `.children` explicitly. Filtering `.tasks[] | select(.parent_id != null)` always returns empty because non-root tasks live under `.children`, not at the top.
- `task:history` returns `{audit_events: [...], workflow_events: [...]}` — there is no top-level `history` array.
- `knowledge:entry:history` returns `{audit_events: [...], workflow_events: [...]}` with the same shape as `task:history`.
- `project:history` returns `{activity_events: [...]}` — a single combined stream, not split by kind.

## Direct Client Fallbacks

Use direct Ruby only when `bin/kos` does not expose the needed operation and the method is listed under Canonical Operations. Keep the load path exactly as shown so Ruby loads the repository client from `lib/kos/client.rb`. The client reads `KOS_BASE_URL` and `KOS_USER_ID` from the environment, prints parsed JSON here, and exits non-zero with the API/client error on failure.

Do not use these fallbacks for operations already listed in CLI Usage. If an operation is missing from both the CLI list and Canonical Operations, stop and report the missing API contract instead of guessing a route.

### List Or Create Users

```bash
KOS_BASE_URL=${KOS_BASE_URL:-http://127.0.0.1:3000} KOS_USER_ID=${KOS_USER_ID:?KOS_USER_ID is required} ruby -Ilib -rkos/client <<'RUBY'
begin
  client = Kos::Client.new
  result = client.list_users
  puts JSON.pretty_generate(result)
rescue Kos::Client::Error, ArgumentError => error
  warn error.message
  exit 1
end
RUBY
```

```bash
KOS_BASE_URL=${KOS_BASE_URL:-http://127.0.0.1:3000} KOS_USER_ID=${KOS_USER_ID:?KOS_USER_ID is required} USER_EMAIL='agent@example.test' USER_DISPLAY_NAME='Agent' ruby -Ilib -rkos/client <<'RUBY'
begin
  client = Kos::Client.new
  result = client.create_user(email: ENV.fetch("USER_EMAIL"), display_name: ENV.fetch("USER_DISPLAY_NAME"))
  puts JSON.pretty_generate(result)
rescue Kos::Client::Error, ArgumentError, KeyError => error
  warn error.message
  exit 1
end
RUBY
```

### Update Task Status Or Priority

Use this only for task fields not covered by documented CLI commands. Workflow transitions must still use `bin/kos task:workflow:transition`.

```bash
KOS_BASE_URL=${KOS_BASE_URL:-http://127.0.0.1:3000} KOS_USER_ID=${KOS_USER_ID:?KOS_USER_ID is required} PROJECT_ID=2 TASK_ID=50 TASK_LOCK_VERSION=6 TASK_STATUS=in_progress TASK_PRIORITY=10 ruby -Ilib -rkos/client <<'RUBY'
begin
  client = Kos::Client.new
  result = client.update_task(
    ENV.fetch("PROJECT_ID"),
    ENV.fetch("TASK_ID"),
    status: ENV["TASK_STATUS"],
    priority: ENV["TASK_PRIORITY"],
    lock_version: ENV.fetch("TASK_LOCK_VERSION")
  )
  puts JSON.pretty_generate(result)
rescue Kos::Client::Error, ArgumentError, KeyError => error
  warn error.message
  exit 1
end
RUBY
```

### List Artifact Types

```bash
KOS_BASE_URL=${KOS_BASE_URL:-http://127.0.0.1:3000} KOS_USER_ID=${KOS_USER_ID:?KOS_USER_ID is required} PROJECT_ID=2 ruby -Ilib -rkos/client <<'RUBY'
begin
  client = Kos::Client.new
  result = client.list_task_artifact_types(ENV.fetch("PROJECT_ID"))
  puts JSON.pretty_generate(result)
rescue Kos::Client::Error, ArgumentError, KeyError => error
  warn error.message
  exit 1
end
RUBY
```

### Read Knowledge Tag Groups

```bash
KOS_BASE_URL=${KOS_BASE_URL:-http://127.0.0.1:3000} KOS_USER_ID=${KOS_USER_ID:?KOS_USER_ID is required} PROJECT_ID=2 ruby -Ilib -rkos/client <<'RUBY'
begin
  client = Kos::Client.new
  result = client.list_tag_groups(ENV.fetch("PROJECT_ID"))
  puts JSON.pretty_generate(result)
rescue Kos::Client::Error, ArgumentError, KeyError => error
  warn error.message
  exit 1
end
RUBY
```

```bash
KOS_BASE_URL=${KOS_BASE_URL:-http://127.0.0.1:3000} KOS_USER_ID=${KOS_USER_ID:?KOS_USER_ID is required} PROJECT_ID=2 TAG_GROUP_ID=1 ruby -Ilib -rkos/client <<'RUBY'
begin
  client = Kos::Client.new
  result = client.get_tag_group(ENV.fetch("PROJECT_ID"), ENV.fetch("TAG_GROUP_ID"))
  puts JSON.pretty_generate(result)
rescue Kos::Client::Error, ArgumentError, KeyError => error
  warn error.message
  exit 1
end
RUBY
```

### Check Knowledge Conflicts

```bash
KOS_BASE_URL=${KOS_BASE_URL:-http://127.0.0.1:3000} KOS_USER_ID=${KOS_USER_ID:?KOS_USER_ID is required} PROJECT_ID=2 TAG_IDS=1,2,3 ruby -Ilib -rkos/client <<'RUBY'
begin
  client = Kos::Client.new
  tag_ids = ENV.fetch("TAG_IDS").split(",").map(&:strip).reject(&:empty?)
  result = client.check_knowledge_conflicts(ENV.fetch("PROJECT_ID"), tag_ids: tag_ids)
  puts JSON.pretty_generate(result)
rescue Kos::Client::Error, ArgumentError, KeyError => error
  warn error.message
  exit 1
end
RUBY
```

### Create, Update, Or Delete Knowledge Entries

```bash
KOS_BASE_URL=${KOS_BASE_URL:-http://127.0.0.1:3000} KOS_USER_ID=${KOS_USER_ID:?KOS_USER_ID is required} PROJECT_ID=2 TAG_IDS=1,2,3 KNOWLEDGE_TITLE='Short title' KNOWLEDGE_SUMMARY='One sentence summary' KNOWLEDGE_BODY='Full guidance body' ruby -Ilib -rkos/client <<'RUBY'
begin
  client = Kos::Client.new
  tag_ids = ENV.fetch("TAG_IDS").split(",").map(&:strip).reject(&:empty?)
  result = client.create_knowledge_entry(
    ENV.fetch("PROJECT_ID"),
    title: ENV.fetch("KNOWLEDGE_TITLE"),
    summary: ENV["KNOWLEDGE_SUMMARY"],
    body: ENV.fetch("KNOWLEDGE_BODY"),
    tag_ids: tag_ids,
    subtopic: ENV["SUBTOPIC"],
    load_policy: ENV["LOAD_POLICY"],
    required_project_bootstrap: ENV["REQUIRED_PROJECT_BOOTSTRAP"],
    required_stages: ENV["REQUIRED_STAGES"]&.split(","),
    required_skills: ENV["REQUIRED_SKILLS"]&.split(",")
  )
  puts JSON.pretty_generate(result)
rescue Kos::Client::Error, ArgumentError, KeyError => error
  warn error.message
  exit 1
end
RUBY
```

```bash
KOS_BASE_URL=${KOS_BASE_URL:-http://127.0.0.1:3000} KOS_USER_ID=${KOS_USER_ID:?KOS_USER_ID is required} PROJECT_ID=2 ENTRY_ID=1 ENTRY_LOCK_VERSION=4 KNOWLEDGE_TITLE='Updated title' KNOWLEDGE_SUMMARY='Updated summary' KNOWLEDGE_BODY='Updated body' ruby -Ilib -rkos/client <<'RUBY'
begin
  client = Kos::Client.new
  result = client.update_knowledge_entry(
    ENV.fetch("PROJECT_ID"),
    ENV.fetch("ENTRY_ID"),
    title: ENV["KNOWLEDGE_TITLE"] || Kos::Client::OMITTED,
    summary: ENV["KNOWLEDGE_SUMMARY"] || Kos::Client::OMITTED,
    body: ENV["KNOWLEDGE_BODY"] || Kos::Client::OMITTED,
    tag_ids: ENV["TAG_IDS"] ? ENV.fetch("TAG_IDS").split(",").map(&:strip).reject(&:empty?) : Kos::Client::OMITTED,
    subtopic: ENV["SUBTOPIC"] || Kos::Client::OMITTED,
    load_policy: ENV["LOAD_POLICY"] || Kos::Client::OMITTED,
    required_project_bootstrap: ENV["REQUIRED_PROJECT_BOOTSTRAP"] || Kos::Client::OMITTED,
    required_stages: ENV["REQUIRED_STAGES"] ? ENV.fetch("REQUIRED_STAGES").split(",") : Kos::Client::OMITTED,
    required_skills: ENV["REQUIRED_SKILLS"] ? ENV.fetch("REQUIRED_SKILLS").split(",") : Kos::Client::OMITTED,
    lock_version: ENV.fetch("ENTRY_LOCK_VERSION")
  )
  puts JSON.pretty_generate(result)
rescue Kos::Client::Error, ArgumentError, KeyError => error
  warn error.message
  exit 1
end
RUBY
```

```bash
KOS_BASE_URL=${KOS_BASE_URL:-http://127.0.0.1:3000} KOS_USER_ID=${KOS_USER_ID:?KOS_USER_ID is required} PROJECT_ID=2 ENTRY_ID=1 ENTRY_LOCK_VERSION=4 ruby -Ilib -rkos/client <<'RUBY'
begin
  client = Kos::Client.new
  result = client.delete_knowledge_entry(ENV.fetch("PROJECT_ID"), ENV.fetch("ENTRY_ID"), lock_version: ENV.fetch("ENTRY_LOCK_VERSION"))
  puts JSON.pretty_generate(result)
rescue Kos::Client::Error, ArgumentError, KeyError => error
  warn error.message
  exit 1
end
RUBY
```

## Identity And Locking

Mutating calls should pass an actor user id when the API requires attribution. `Kos::Client.new(user_id: user_id)` sends it as `X-User-Id`.

For local `mise`-managed repositories, configure the actor once in the parent workspace `mise.toml` so all nested project sessions inherit it:

```toml
[env]
KOS_USER_ID = "1"
```

Use the id of an existing KOS user. If `KOS_USER_ID` is missing, mutating `bin/kos` commands such as `task:claim-next`, workflow transitions, artifact writes, and knowledge updates must stop with the API error `Authentication required` instead of retrying unauthenticated or inventing an identity.

Operations that update workflow state, final git trace, task specs, existing artifacts, or knowledge entries must include the latest `lock_version` from the work package or read response. Initial artifact creation may omit `lock_version` because no existing artifact can be stale. If the API rejects the request because the lock is missing or stale, reload the relevant task, artifact, or knowledge entry only when the orchestrator or caller requested that retry path; otherwise return the error so the orchestrator can make the conflict decision.

## Canonical Operations

### Users And Identity

- `list_users`
- `get_user(user_id)`
- `create_user(email:, display_name:)`

### Projects

- `list_projects`
- `get_project(project_id)`
- `get_project_by_slug(slug)`
- `resolve_or_create_project(slug:, name:)`
- `current_repository_project_identity(cwd:)`
- `resolve_or_create_current_project(cwd:)`
- `get_project_roadmap(project_id)`

### Tasks

- `list_tasks(project_id)`
- `get_task(project_id, task_id)`
- `next_actionable_task(project_id, mode: nil)`
- `claim_next_actionable_task(project_id, mode: nil)`
- `get_task_work_package(project_id, task_id)`
- `create_task(project_id, title:, body:, status:, parent_id:)`
- `write_task_spec(project_id, task_id, body:, lock_version:)`
- `update_task(project_id, task_id, status:, workflow_status:, lock_version:, priority:)`
- `transition_task_workflow(project_id, task_id, workflow_status:, lock_version:)`
- `finalize_task_git_trace(project_id, task_id, git_branch:, git_commit_sha:, git_commit_message:, git_commit_observed_at:, lock_version:)`
- `finalize_task_no_op_git_handoff(project_id, task_id, no_op_reason:, lock_version:)`
- `record_task_orchestration_run(project_id, task_id, trace:)`

### Task Agent Artifacts

- `list_task_artifact_types(project_id)`
- `list_task_artifacts(project_id, task_id)`
- `get_task_artifact(project_id, task_id, artifact_type)`
- `write_task_artifact(project_id, task_id, artifact_type, body:, lock_version:)`

### Knowledge And Retrieval

- `list_tag_groups(project_id)`
- `get_tag_group(project_id, tag_group_id)`
- `list_tags(project_id)`
- `check_knowledge_conflicts(project_id, tag_ids:)`
- `list_knowledge_entries(project_id)`
- `get_knowledge_entry(project_id, entry_id)`
- `create_knowledge_entry(project_id, title:, body:, summary:, tag_ids:, subtopic:, subtopic_tag_id:, load_policy:, required_project_bootstrap:, required_stages:, required_skills:)`
- `update_knowledge_entry(project_id, entry_id, title:, body:, summary:, tag_ids:, subtopic:, subtopic_tag_id:, load_policy:, required_project_bootstrap:, required_stages:, required_skills:, lock_version:)`
- `delete_knowledge_entry(project_id, entry_id, lock_version:)`
- `search(project_id, query:, tag_ids:)`
- `get_knowledge_context(project_id, task_id:, stage:, skill:, limit:, subtopic:)`

Use `list_tags` as the first retrieval preflight for agent workflows. Its tag group and tag descriptions are part of the API contract: agents use them to decide which `kind`, `scope`, and `topic` tags describe a needed context query before calling `search` or validating a `get_knowledge_context` bundle. Do not hard-code knowledge article titles such as bootstrap articles as the retrieval path.

The `kind`, `scope`, and `topic` groups are closed and curated — `list_tags` returns the canonical dictionary, and `ManageTag.create` rejects new tags inside them. The `subtopic` group is open-vocabulary: `list_tags` returns subtopic values that have been used at least once in the current project (autocomplete-style discovery, not a canonical dictionary). To attach a subtopic, pass `subtopic:` (free-form string — normalized to `lowercase + _`) or `subtopic_tag_id:` (existing tag id) to `create_knowledge_entry` / `update_knowledge_entry`. Two entries that share `{kind,scope,topic}` but differ in `subtopic` are no longer identity-conflicting; existing entries without a subtopic keep today's identity_key shape.

For routine workflows, load this dictionary with `bin/kos knowledge:tags PROJECT_ID` instead of probing CLI help or using ad hoc Ruby.

Required bootstrap articles must be created or updated through the same knowledge APIs with `load_policy: "required"`. Use `required_project_bootstrap: true` for the project's constitution article: the expanded KOS-native main law of the project that defines purpose, operating principles, source-of-truth rules, mandatory workflow expectations, quality gates, and stop conditions. The constitution must not be a copy of the thin replacement `AGENTS.md`; `AGENTS.md` only tells a stateless agent how to enter KOS, while the constitution explains the durable project rules that every agent must load before normal work. Use `required_stages` or `required_skills` only when an article is mandatory for specific workflow stages or KOS skills.

### History

- `get_project_history(project_id)`
- `get_task_history(project_id, task_id)`
- `get_knowledge_entry_history(project_id, entry_id)`

## Workflow

1. Resolve `KOS_BASE_URL` and actor identity.
2. Use `kos-standard-agent` for routine documented `bin/kos` calls when the runtime exposes it; otherwise run the documented command directly and note that `kos-standard-agent` was unavailable.
3. Use `bin/kos` for routine supported operations; initialize `Kos::Client` with `base_url` and `user_id` only when direct Ruby access is needed.
4. When the caller omits project input, call `bin/kos project:resolve-current` or `resolve_or_create_current_project(cwd:)` and use the returned project id or slug for downstream project-scoped operations.
5. Prefer one canonical client method per API operation.
6. Preserve public artifact type keys instead of Rails STI class names.
7. Send `lock_version` for every lock-protected write; reload the relevant resource first if no current lock is available.
8. Return the parsed JSON result to the calling skill.
9. On API errors, surface the error text and let the orchestrator decide whether to reload, ask the human, or stop.

## Examples

### Claim Or Resume Work

```bash
bin/kos project:resolve-current
bin/kos task:claim-next PROJECT_ID
bin/kos task:work-package PROJECT_ID TASK_ID
```

`claim_next_actionable_task` first returns the current actor's already claimed unfinished work package when one exists for the selected queue. If none exists, it claims the next work item from deterministic task queues. Default `mode: nil` behaves as `any`: execution queue first, then specification/brainstorm queue. Callers may pass `mode: "execution"` to restrict selection to implementation-ready workflow statuses or `mode: "specification"` to restrict selection to idea/specification work. Container tasks are never auto-claimed.

### Write A Development Plan

```bash
bin/kos artifact:write PROJECT_ID TASK_ID development_plan - --lock-version ARTIFACT_LOCK_VERSION
```

### Write A Task Spec

```bash
bin/kos task:spec:write PROJECT_ID TASK_ID TASK_LOCK_VERSION -
```

### Transition Workflow State

```bash
bin/kos task:workflow:transition PROJECT_ID TASK_ID testing TASK_LOCK_VERSION
```

### Retrieve Knowledge Context

```bash
bin/kos knowledge:tags PROJECT_ID
bin/kos search PROJECT_ID workflow artifact rules --tag-ids ID,ID
bin/kos knowledge:context PROJECT_ID --task-id TASK_ID --stage planning --skill kos-plan
```

### Persist Git Handoff

```bash
bin/kos task:git-trace:finalize PROJECT_ID TASK_ID main COMMIT_SHA "Commit message" 2026-05-02T08:03:24Z TASK_LOCK_VERSION
bin/kos task:git-handoff:no-op PROJECT_ID TASK_ID "No repository diff; KOS artifacts only" TASK_LOCK_VERSION
```

### Read Artifacts And History

```bash
bin/kos artifact:list PROJECT_ID TASK_ID
bin/kos artifact:get PROJECT_ID TASK_ID verification_report
bin/kos task:history PROJECT_ID TASK_ID
```

## Stop Conditions

Stop and return control to the calling orchestrator when:

- the API server is unavailable
- actor identity is missing for a mutating operation that requires attribution
- a stale lock version or conflict response requires a reload or human decision
- the requested operation is not represented by the current API or `Kos::Client`
- an API response is missing data the calling workflow requires to continue safely

## Verification

Verify this skill by:

- checking that each documented operation maps to `lib/kos/client.rb`
- running `bundle exec rspec spec/lib/kos/cli_spec.rb` after CLI command changes
- running `bundle exec rspec spec/lib/kos/client_spec.rb` after client operation changes
- running request specs for any API endpoint behavior changed by a task
- validating examples against the current client method signatures when they are changed
