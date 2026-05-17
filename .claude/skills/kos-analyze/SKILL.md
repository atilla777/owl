---
name: kos-analyze
description: Analyze the solution space for the active task (analyzing stage) and persist acceptance_criteria, analysis_report, and (Container only) outgoing_tasks artifacts.
---

# Skill: kos-analyze

## Purpose

`kos-analyze` is the `analyzing`-stage skill across the three workflow types that declare an analyzing stage: `Container workflow`, `Feature workflow`, and `Bugfix workflow`.

Use it to convert clarified intent into explicit acceptance criteria and a solution-space analysis; for Container tasks only, also produce the concrete `outgoing_tasks` artifact that spawns child Development tasks when the container reaches `done`.

## When To Use

Use this skill when the current task's workflow_status is `analyzing` (any of Container / Feature / Bugfix), or when a Container task is in `ready_to_plan` and `outgoing_tasks` still needs work.

Do not use this skill for initial intent capture (use `kos-specify`), for open-question resolution (use `kos-clarify` — Container or Feature only; Bugfix has no clarifying stage), or for any Subtask task. Subtask workflow does not declare an `analyzing` stage; if invoked against a Subtask, stop and return a blocker.

## Modes

The skill behaves differently per AgentWorkflowType. The orchestrator must pass `agent_workflow_type.name` in the dispatch packet so this skill can select the correct mode.

### Container mode (`Container workflow`)

- Required input artifacts: `intent_brief`, `clarification_log`
- Output artifacts: `acceptance_criteria`, `analysis_report`, `outgoing_tasks`
- `analysis_report` sections: `Approach options`, `Selected approach`, `Risks`
- `outgoing_tasks` is required before leaving `ready_to_plan`; each entry must carry `title`, `body`, and a `spec_body` shaped per the Subtask `specification` template
- Recommended next status when all three are approved: `ready_to_plan`; then `done` to trigger `SpawnOutgoingTasks`

### Feature mode (`Feature workflow`)

- Required input artifacts: `specification`, `clarification_log`
- Output artifacts: `acceptance_criteria`, `analysis_report`
- `analysis_report` sections: `Approach options`, `Selected approach`, `Risks`
- `outgoing_tasks` MUST NOT be produced; Feature tasks do not spawn children
- Recommended next status when both are approved: `planning`

### Bugfix mode (`Bugfix workflow`)

- Required input artifact: `specification` (no clarification_log — Bugfix has no clarifying stage)
- Output artifacts: `acceptance_criteria`, `analysis_report`
- `analysis_report` sections are root-cause-shaped: `Root Cause`, `Fix Scope`, `Regression Risk`, `Mitigations` (per `EnsureBugfixWorkflowType::BUGFIX_ANALYSIS_REPORT_TEMPLATE`)
- `outgoing_tasks` MUST NOT be produced; Bugfix tasks do not spawn children
- Recommended next status when both are approved: `planning`

### Subtask mode

Blocked. Subtask workflow has no `analyzing` stage. Return a blocker if invoked.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- Treat `kos-brainstorm` as the conversational backbone.
- Treat existing `intent_brief` and `clarification_log` artifacts as inputs; do not silently override their decisions.
- Return artifact bodies to the orchestrator; do not write artifacts or transition workflow state directly.

## Inputs

- task id, title, body, workflow status, and lock version
- `agent_workflow_type.name` — selects Container / Feature / Bugfix mode
- current intake artifact: `intent_brief` (Container) or `specification` (Feature / Bugfix); required
- current `clarification_log` artifact (Container and Feature only; required for those modes)
- existing `acceptance_criteria`, `analysis_report`, or (Container only) `outgoing_tasks` artifacts when present
- required KOS knowledge context bundle for the `analyzing` stage

## Outputs

- proposed `acceptance_criteria` artifact body with required sections `Criteria`, `Out of scope` (all modes)
- proposed `analysis_report` artifact body:
  - Container / Feature: `Approach options`, `Selected approach`, `Risks`
  - Bugfix: `Root Cause`, `Fix Scope`, `Regression Risk`, `Mitigations`
- proposed `outgoing_tasks` artifact body with required section `Tasks` and YAML frontmatter `outgoing_tasks` array of `{title, body, spec_body}` entries — **Container mode only**
- recommended next workflow status:
  - Container: `ready_to_plan` once all three are approved, then `done` to trigger spawn
  - Feature / Bugfix: `planning` once acceptance_criteria and analysis_report are approved

## Discussion Workflow

1. Read `agent_workflow_type.name` from the dispatch packet and select the mode.
2. Re-read the intake artifact (`intent_brief` for Container; `specification` for Feature / Bugfix) and, for Container/Feature modes, the `clarification_log`.
3. Load the required KOS knowledge context bundle.
4. Draft acceptance criteria first — they constrain the analysis.
5. Sketch the solution space and produce the mode-shaped `analysis_report`:
   - Container / Feature: compare approach options, name the selected approach, and surface risks.
   - Bugfix: identify root cause, define fix scope, assess regression risk, list mitigations.
6. **Container mode only**: decompose the work into child task entries. Each entry must include a concrete `title`, a short `body` (work item description), and a `spec_body` (markdown matching the Subtask `specification` template: required sections `Local goal`, `Local AC`, `Implementation notes`) so `SpawnOutgoingTasks` can seed each child cleanly.
7. Return the artifact bodies and recommended transition to the orchestrator.

## Outgoing Tasks Format

The `outgoing_tasks` artifact must carry the spawn payload in its frontmatter:

```yaml
---
status: approved
summary: Five child tasks for ...
outgoing_tasks:
  - title: "Short title"
    body: "Why this child task exists"
    spec_body: |
      ---
      status: approved
      summary: ...
      ---
      ## Intent
      ...
      ## Acceptance criteria
      ...
      ## Non-goals
      ...
      ## Open questions
      ...
      ## Scope
      ...
---

## Tasks

- ... (human-readable summary of the planned children)
```

The markdown body is for humans; the spawn service reads only the frontmatter.

## Stop Conditions

Stop and return a clear blocker to the orchestrator when:

- `agent_workflow_type.name` is missing or is not one of `Container workflow`, `Feature workflow`, or `Bugfix workflow` (Subtask workflow is unsupported here — block immediately)
- the required intake artifact for the selected mode is missing (`intent_brief` for Container; `specification` for Feature / Bugfix)
- the required `clarification_log` is missing for Container or Feature modes
- Container mode decomposition would require splitting the container further (return scope decision to the human)
- a Feature or Bugfix analysis surfaces work that does not fit a single Development task (recommend converting to a Container, do not silently spawn)
- required KOS knowledge context is missing or blocked

## Persistence Responsibilities

This skill returns mode-appropriate artifact bodies. The orchestrator persists each through `kos-api.write_task_artifact` and applies workflow transitions, including the Container-mode `ready_to_plan → done` transition that triggers `SpawnOutgoingTasks`.

## Verification

Verify this skill by checking that:

- the selected mode matches `agent_workflow_type.name`
- each artifact body validates against its mode-specific template (Bugfix `analysis_report` uses the root-cause sections, not the Container/Feature ones)
- `outgoing_tasks` is produced only in Container mode and never in Feature or Bugfix mode
- every Container-mode `outgoing_tasks` entry has a `spec_body` matching the Subtask `specification` template
- the skill does not silently transition workflow status or spawn children directly
