---
name: kos-completion-report
description: Produce the final user-facing completion report artifact for a finished KOS task.
---

# Skill: kos-completion-report

## Purpose

`kos-completion-report` is the workflow stage skill for producing the final user-facing completion report artifact for a finished task.

Use it to explain what changed for the human after code, verification, review, and git handoff are complete.

## When To Use

Use this skill after successful git handoff, or when the task reaches the configured completion point and the workflow supports a `completion_report` artifact.

Do not use this skill to perform review, rerun verification, commit changes, or mark incomplete work as done.

## Source Of Truth

- Any final user-facing report, stop report, blocker report, or completion summary emitted from this skill or through the orchestrator must be written in Russian.
- The report must include a plain-language section explaining what changed from the end user's perspective, not only technical files or commands.

- When work uncovers a repeatable project-specific pitfall, API behavior, workflow gotcha, verification issue, or other lesson that would prevent future mistakes, treat it as durable knowledge rather than private memory.
- Classify these entries with taxonomy `kind: nuance` and select existing `scope` and `topic` tags from `kos-api.list_tags`; do not invent taxonomy tags or free-form "what I learned" labels.
- Stage skills should return durable nuance candidates to the orchestrator. The orchestrator persists them through `kos-api.check_knowledge_conflicts` followed by `create_knowledge_entry` or `update_knowledge_entry` when the knowledge is not already captured.

- Use the task spec, development plan, verification summary, review report, and git trace as source material.
- Focus on product, user-visible, operator-visible, or workflow-visible changes rather than only technical file lists.
- Do not require a KOS knowledge context bundle for completion reporting; use project knowledge only when it is already loaded and relevant.
- Start from the orchestrator-provided completion packet; do not claim tasks, select workflow stages, or make hidden KOS mutations while reporting.
- Return the report body to the orchestrator; do not secretly transition workflow state.

## Inputs

- task id, title, spec body, and final workflow status candidate
- `development_plan` artifact
- verification summary
- `review_report` artifact, when supported
- git trace payload
- changed-file summary, when useful as secondary detail
- optional KOS knowledge context bundle when project-specific reporting conventions already exist

## Outputs

- Russian `completion_report` artifact body in Markdown
- short final Russian human-readable summary
- any follow-up recommendations or residual risks
- recommended next workflow status, usually `done`

## Completion Report Shape

Use this structure unless the workflow defines a different one:

```markdown
# Отчет о завершении

## Что изменилось для конечного пользователя

- <Plain-language end-user-visible change or "Пользовательский сценарий не изменился", when applicable>

## Что изменилось для оператора или разработчика

- <Operator-visible, workflow-visible, or technical capability change>

## Проверено

- <Check that was run or behavior that was confirmed>

## Git Trace

- Branch: <branch>
- Commit: <sha>
- Message: <message>

## Дальнейшие шаги

- <Follow-up, residual risk, or "Нет">
```

## Workflow

1. Read the final task work package and relevant artifacts.
2. Treat missing or empty KOS knowledge context as acceptable for completion reporting.
3. Summarize the delivered outcome in Russian plain language.
4. Include verification results and git trace.
5. Note residual risks or natural follow-up tasks without inventing speculative work.
6. Return the Russian `completion_report` body and final human summary to the orchestrator.
7. Recommend transition to `done` only when required handoff and reporting inputs are present.

## Stop Conditions

Stop and return a clear blocker to the orchestrator when:

- git handoff was expected but no successful git trace is available
- verification or review results contain unresolved blockers
- the task outcome is ambiguous enough that a plain-language report would be misleading
- the workflow does not support the `completion_report` artifact and no alternate persistence path is defined

## Persistence Responsibilities

This skill produces the `completion_report` body and final human summary. The orchestrator persists the artifact through `kos-api`, transitions the task to `done`, and reports the final result to the human.

## Verification

Verify this skill by checking that:

- the report is written in Russian
- the report explains end-user-visible changed behavior or explicitly says the end-user scenario did not change
- the report explains changed behavior or capabilities, not just filenames
- verification and git trace details are accurate
- follow-ups are concrete and not speculative
- the artifact key remains `completion_report`
