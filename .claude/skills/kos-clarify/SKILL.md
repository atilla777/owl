---
name: kos-clarify
description: Resolve open questions for a Specification-workflow container task (clarifying stage) and persist the clarification_log artifact.
---

# Skill: kos-clarify

## Purpose

`kos-clarify` is the `clarifying`-stage skill of the KOS Specification workflow.

Use it to drive an explicit clarification round between the human and the agent so a container task moves from "we know the intent" to "open questions are answered" before analysis begins.

## When To Use

Use this skill when the current task uses the `Specification workflow` AgentWorkflowType and is in workflow status `clarifying`.

Do not use this skill to capture initial intent (use `kos-specify`), to decompose the solution space (use `kos-analyze`), or for any execution-flow stage.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- Treat `kos-brainstorm` as the conversational backbone.
- Treat the existing `intent_brief` artifact as the source of intent and avoid re-litigating it during clarification.
- Return the artifact body to the orchestrator; do not write artifacts or transition workflow state directly.

## Inputs

- task id, title, body, workflow status, and lock version
- current `intent_brief` artifact (required input)
- existing `clarification_log` artifact when present
- required KOS knowledge context bundle for the `clarifying` stage

## Outputs

- proposed `clarification_log` artifact body in Markdown with required sections `Open questions`, `Answers`, `Decisions`
- one-line summary
- recommended next workflow status, usually `analyzing` once open questions are addressed

## Discussion Workflow

1. Re-read the `intent_brief` and any existing `clarification_log`.
2. Confirm the required KOS knowledge context bundle is loaded.
3. List concrete open questions blocking analysis.
4. Capture the human's answers and decisions verbatim or as concise paraphrases.
5. Draft or update the log artifact body with the three required sections.
6. Return the body and recommended transition to the orchestrator.

## Stop Conditions

Stop and return a clear blocker to the orchestrator when:

- the task is not on the Specification workflow
- the `intent_brief` artifact is missing
- a clarification answer would change the intent in a way that requires returning to `exploring`
- required KOS knowledge context is missing or blocked

## Persistence Responsibilities

This skill returns the proposed `clarification_log` body. The orchestrator persists it through `kos-api.write_task_artifact` and applies workflow transitions.

## Verification

Verify this skill by checking that:

- the artifact body validates against the `clarification_log` template
- the log captures both unresolved and resolved items distinctly
- the skill does not silently transition workflow status
