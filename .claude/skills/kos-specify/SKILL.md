---
name: kos-specify
description: Capture initial intent or specification for the active KOS task (exploring/specifying stage) and persist the intent_brief or specification artifact.
---

# Skill: kos-specify

## Purpose

`kos-specify` is the intake-stage skill that turns the raw task body into the first durable agent-authored artifact the workflow requires before clarification, analysis, or planning can begin.

Use it when the active task is on its first agent-authored stage and needs either an `intent_brief` (Container) or a `specification` (Feature / Bugfix) artifact.

## When To Use

Use this skill when the current task's workflow_status matches the intake stage of one of the four canonical AgentWorkflowTypes:

- `Container workflow` in status `exploring` (or being moved from `idea` to `exploring`) — produce `intent_brief`.
- `Feature workflow` in status `specifying` — produce `specification` with the Feature-shaped sections.
- `Bugfix workflow` in status `specifying` — produce `specification` with the Bugfix-shaped sections.

Subtask workflow specifications are produced by the parent Container's `kos-analyze` stage as `outgoing_tasks` `spec_body` payloads and are seeded by `Tasks::Services::SpawnOutgoingTasks`; this skill does not author a Subtask specification from scratch. If invoked against a Subtask in `specifying`, treat the seeded specification body as authoritative and only edit it to fill clearly missing required sections, then stop and hand back to the orchestrator.

Do not use this skill for execution-flow planning, implementation, verification, review, or for any stage other than the intake stage above.

## Modes

The skill behaves differently per AgentWorkflowType. The orchestrator must pass `agent_workflow_type.name` in the dispatch packet so this skill can select the correct mode without guessing.

### Container mode (`Container workflow`)

- Artifact key: `intent_brief`
- Required sections: `Problem`, `Desired outcome`, `Constraints`
- Frontmatter: `status` (enum `draft` / `approved`), `summary`
- Recommended next status when approved: `clarifying`

### Feature mode (`Feature workflow`)

- Artifact key: `specification`
- Required sections: `Intent`, `Acceptance criteria`, `Non-goals`, `Open questions`, `Scope`, `Edge cases`, `Ambiguities`, `Consistency checks`
- Frontmatter: matches the default `specification` template (`status`, `summary`, plus optional `acceptance_criteria_ids` array)
- Recommended next status when approved: `clarifying`

### Bugfix mode (`Bugfix workflow`)

- Artifact key: `specification`
- Required sections: `Current Behavior`, `Expected Behavior`, `Unchanged Behavior`, `Affected Versions`, `Reproduce Steps`
- Frontmatter: matches the default `specification` template
- Recommended next status when approved: `analyzing` (Bugfix workflow skips a dedicated clarifying stage; resolve open questions inline during specification)

### Subtask mode (`Subtask workflow`)

- Artifact key: `specification`
- Required sections: `Local goal`, `Local AC`, `Implementation notes`
- Frontmatter: matches the subtask `specification` template (`status`, `summary`, optional `acceptance_criteria_ids`)
- Behavior: do not author from scratch. The body is pre-seeded by `SpawnOutgoingTasks` from the parent Container's `outgoing_tasks` artifact. Fill missing required sections only if the seed body is incomplete, then recommend transition to `planning`.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- Treat `kos-brainstorm` as the conversational backbone: the same project-resolution, knowledge-context loading, and discussion patterns apply.
- Treat the loaded task work package as authoritative; do not infer intent from outside files.
- Return the artifact body to the orchestrator; do not write artifacts or transition workflow state directly.

## Inputs

- task id, title, body, workflow status, and lock version
- `agent_workflow_type.name` (one of `Container workflow`, `Feature workflow`, `Bugfix workflow`, `Subtask workflow`) — selects the mode above
- existing `intent_brief` or `specification` artifact when present
- task spec body or initial idea text from the work package
- required KOS knowledge context bundle for the active intake stage (`exploring` for Container, `specifying` for the rest)

## Outputs

- proposed artifact body in Markdown, validating against the template selected by the active mode
- artifact key: `intent_brief` (Container mode) or `specification` (Feature / Bugfix / Subtask modes)
- one-line summary (used as `summary` in frontmatter)
- recommended next workflow status: `clarifying` (Container, Feature), `analyzing` (Bugfix), or `planning` (Subtask)

## Discussion Workflow

1. Read `agent_workflow_type.name` from the dispatch packet and select the mode.
2. Re-read the idea body and any existing artifact for the selected mode (`intent_brief` for Container, `specification` for the others).
3. Confirm the required KOS knowledge context bundle is loaded.
4. Ask the smallest number of clarifying questions needed to write a useful intake artifact; defer deeper clarification work to `kos-clarify` for Container and Feature modes (Bugfix has no dedicated clarifying stage, so resolve essential ambiguities inline).
5. Draft the artifact body with the required sections for the selected mode plus a concise summary.
6. Return the body, the chosen artifact key, and the recommended transition to the orchestrator.

## Stop Conditions

Stop and return a clear blocker to the orchestrator when:

- `agent_workflow_type.name` is missing from the dispatch packet or is not one of the four canonical workflow type names
- the active task's workflow_status does not match the intake stage of its workflow type
- the idea body and conversation cannot establish the required sections for the selected mode (e.g. no reproducible steps for Bugfix, no acceptance criteria draft for Feature)
- a Feature task surfaces a clarification that materially changes intent and needs to wait for `kos-clarify` — return the open question rather than silently writing it into the spec
- required KOS knowledge context is missing or blocked
- the work package lacks the lock data needed for safe persistence

## Persistence Responsibilities

This skill returns the proposed artifact body and the chosen artifact key. The orchestrator persists it through `kos-api.write_task_artifact` and applies workflow transitions.

## Verification

Verify this skill by checking that:

- the selected mode matches `agent_workflow_type.name` from the dispatch packet
- the artifact body validates against the template for the selected mode (required sections + frontmatter schema)
- the artifact key matches the mode (`intent_brief` for Container, `specification` for Feature / Bugfix / Subtask)
- unresolved scoping questions are surfaced as blockers instead of being hidden in the artifact
- the skill does not silently transition workflow status
