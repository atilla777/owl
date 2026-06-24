# Goal

Реализовать условные шаги по design: поле `when:` на шаге, `ConditionEvaluator`,
классификация ready-steps (conditional_skip-бакет), действие `skip_conditional_step` в
`owl next`, обработка в оркестраторе. `ready_resolver` остаётся чистым; `owl step skip`
переиспользуется как есть.

# Scope

- Схема: `when` на шаге в `schemas/workflow.json` + `owl workflow validate`.
- `ConditionEvaluator` (internal, читает артефакт через слой).
- Классификация ready-steps + `next` action `skip_conditional_step`.
- Оркестратор-skill: ветка обработки.
- Тесты + bump `Owl::VERSION` (minor) + CHANGELOG.

# Constraints

- `ready_resolver.rb` НЕ менять (остаётся чистым); предикат вычисляется в слое с `root`.
- `owl next` остаётся read-only — возвращает действие, не мутирует.
- `owl step skip` НЕ требует `optional` (проверено) — переиспользовать.
- Шаги без `when:` — поведение идентично прежнему (back-compat).
- Отсутствующий артефакт → `met: false` (авто-skip, безопасный дефолт).
- Артефакт читать через `Owl::Artifacts`/`Owl::Storage`, не прямым FS.
- 100% покрытие затронутых `**/api.rb`; minor bump + CHANGELOG.
- v1 предикат: `artifact` + ровно один из `matches`/`not_matches` (regex по телу).

# Checklist

1. **Схема.** В `schemas/workflow.json` добавить на шаге опциональное `when`
   (object: `artifact` string required, `matches`/`not_matches` string, oneOf). В
   `WorkflowValidator` — проверка формы (ровно один оператор, regex компилируется;
   warning если `when.artifact` не объявлен в `artifacts`).
2. **ConditionEvaluator.** `Owl::Workflows::Internal::ConditionEvaluator.evaluate(
   root:, task_id:, predicate:)` → `Result.ok(met:)`/`Result.err(:invalid_condition)`.
   Читает тело артефакта через слой; regex match/not_match; отсутствующий артефакт →
   `met: false`.
3. **Классификация ready-steps.** В пути `Owl::Workflows::Api.ready_steps` (backend) —
   после получения `ready` из `ready_resolver`, для каждого ready-шага с `when:`
   вычислить предикат: истина → остаётся в `ready`; ложь → переносится в новый бакет
   `conditional_skip: [{id, reason: "condition_unmet"}]`. Прокинуть `root`/`task_id`
   куда нужно.
4. **next action.** В `next_action_resolver`: если верхний кандидат — conditional_skip,
   вернуть `action.kind: "skip_conditional_step" {task_id, step_id, reason}` (зеркало
   `await_plan_approval_action`). Учесть приоритет относительно dispatch.
5. **Оркестратор-skill.** В `skills/owl-orchestrator/SKILL.md` (+ `.owl` синхро) —
   ветка на `skip_conditional_step`: `owl step skip TASK STEP --reason condition_unmet`,
   затем re-resolve (`owl next`). Документировать.
6. **Тесты:** when-true→ready+dispatch; when-false→conditional_skip+next action+skip
   разблокирует зависимые; not_matches; отсутствующий артефакт→skip; невалидная форма
   `when`→workflow validate ошибка; back-compat (шаг без when). Покрыть новые ветки
   `**/api.rb` до 100%.
7. Bump `Owl::VERSION` (minor) + `CHANGELOG.md`.

# Files to inspect

- `lib/owl/workflows/internal/ready_resolver.rb` (НЕ менять — понять контракт),
  `lib/owl/workflows/api.rb` + backend (`ready_steps` — где строятся бакеты).
- `lib/owl/orchestration/internal/next_action_resolver.rb` (`classify` + action kinds).
- `lib/owl/workflows/internal/workflow_validator.rb` (валидация `when`).
- `schemas/workflow.json`.
- `lib/owl/artifacts/api.rb` / `lib/owl/storage/api.rb` — чтение тела артефакта.
- `lib/owl/steps/api.rb` (`skip` — переиспользуется, не менять).
- `skills/owl-orchestrator/SKILL.md` (+ `.owl/`/`.claude/` синхро через owl upgrade позже).
- `spec/owl/workflows/**`, `spec/owl/orchestration/**`, `spec/owl/cli/**`.
- `lib/owl/version.rb`, `CHANGELOG.md`.

# Tests and verification

- Юнит/CLI на все сценарии (checklist 6).
- `bundle exec rspec` зелёный (после — `git checkout README.md`).
- 100% покрытие затронутых `**/api.rb`; RuboCop net-zero.

# Smoke test

```
# Workflow с шагом: when: { artifact: brief, matches: "needs design" }
# brief БЕЗ "needs design":
owl task ready-steps TASK --json     # шаг в conditional_skip, не в ready
owl next TASK --json                  # action.kind: skip_conditional_step
owl step skip TASK design --reason condition_unmet
owl next TASK --json                  # следующий шаг (зависимый) разблокирован
# brief С "needs design": шаг в ready, dispatch_step
```

# Out of scope

- Циклы/ветвление-на-несколько-путей/sub-workflow/параметры шага (F2.2 отложено).
- Идемпотентный spec merge (TASK-0029). Богатый язык предикатов (and/or/frontmatter).
