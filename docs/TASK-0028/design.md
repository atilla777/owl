---
status: shipped
summary: "when:-предикат на шаге (artifact + matches/not_matches); вычисляется в слое с root; false→next возвращает skip_conditional_step→оркестратор делает owl step skip (существующий API). ready_resolver остаётся чистым."
---

# Context

P2-A добавляет первую условную логику в статичный движок. Ключевое ограничение:
`ready_resolver` — чистая функция без доступа к артефактам, её нельзя «загрязнять» FS.
Поэтому предикат вычисляется в слое, где есть `root` (orchestration/steps), а
`ready_resolver` не трогаем. Существующий `owl step skip` НЕ требует `optional`
(проверяет лишь non-done) — значит авто-skip переиспользует его как есть.

# Decision

1. **Поле `when:` на шаге workflow.** Форма (v1, минимальная):
   ```
   when:
     artifact: <artifact-key>        # ключ ранее созданного артефакта
     matches: "<regex>"              # ИЛИ
     not_matches: "<regex>"
   ```
   Ровно один из `matches`/`not_matches`. Истинность: тело артефакта `artifact`
   соответствует (или НЕ соответствует) regex. `schemas/workflow.json` расширяется
   полем `when` на шаге; `owl workflow validate` проверяет форму (ровно один оператор,
   regex компилируется, `artifact` непустой).

2. **ConditionEvaluator (internal, с доступом к артефактам).**
   `Owl::Workflows::Internal::ConditionEvaluator.evaluate(root:, task_id:, predicate:)`
   → `Result.ok(met: true|false)` или `Result.err(:invalid_condition)`. Читает тело
   артефакта через слой (`Owl::Artifacts`/`Owl::Storage`/`owl artifact resolve`-эквивалент),
   НЕ прямым FS. **Отсутствующий артефакт → `met: false`** (безопасный дефолт: не
   wedge'ить, авто-skip с пометкой про отсутствие).

3. **ready_resolver не меняется.** Предикат вычисляется ВЫШЕ — в пути, где собираются
   ready-steps с `root` (`Owl::Workflows::Api`/`Tasks::Api.ready_steps` или
   orchestration). Для каждого «иначе-готового» шага с `when:`:
   - предикат истинен → шаг остаётся в `ready` (диспетчеризуется обычно);
   - предикат ложен → шаг ИСКЛЮЧАЕТСЯ из `ready` и помечается отдельно
     (`conditional_skip`-бакет в `ready-steps`).

4. **`owl next` (read-only) → новое действие.** Когда верхний готовый шаг — условный с
   ложным предикатом, `next` возвращает `action.kind: "skip_conditional_step"`
   `{task_id, step_id, reason: "condition_unmet"}` (зеркало `await_plan_approval`).
   Мутацию делает оркестратор: `owl step skip TASK-ID STEP-ID --reason condition_unmet`
   (существующий API; skipped разблокирует зависимые как done).

5. **Оркестратор-skill.** Добавить ветку на `skip_conditional_step`: выполнить
   `owl step skip`, затем повторить цикл (`owl next`). Документировать в
   `skills/owl-orchestrator`.

6. **Обратная совместимость.** Шаг без `when:` — путь не меняется (предикат не
   вычисляется). Существующие workflow/задачи не затронуты.

# Alternatives

- **Вычислять `when:` внутри `ready_resolver`.** Отвергнуто: нарушает чистоту
  резолвера (он не должен читать FS/артефакты), усложняет тестирование.
- **`owl next` авто-skip'ает сам (мутирует).** Отвергнуто: `next` контрактно
  read-only; мутация — обязанность оркестратора (как для plan-approval).
- **Богатый язык предикатов (and/or, frontmatter, JSONPath).** Отложено: v1 —
  artifact+regex; расширяемо позже без слома схемы.
- **Расширять валидацию `step skip` под conditional.** Не нужно: `skip` уже не требует
  `optional`.

# Risks

- **Изменение классификации ready-steps / next.** Затрагивает ядро выбора работы;
  митигируется тем, что для шагов без `when:` поведение идентично, и покрытием тестами
  обоих путей.
- **Стоимость чтения артефакта на резолве.** Только для шагов с `when:` и только когда
  они иначе-готовы; дёшево.
- **Отсутствующий артефакт → skip.** Может скрыть мисконфиг workflow; митигируется
  пометкой причины и валидацией `when.artifact` на `workflow validate` (предупреждение,
  если ключ не объявлен в `artifacts`).
- **Покрытие api.rb.** Новые ветки в затронутых `**/api.rb` покрыть до 100%.

# API

- Workflow YAML: `steps[].when: { artifact, matches|not_matches }`.
- `owl workflow validate <id>` — проверяет форму `when`.
- `owl task ready-steps TASK-ID --json` — добавляет бакет
  `conditional_skip: [{id, reason}]` (наряду с `ready`/`blocked_by_children`/
  `awaiting_plan_approval`).
- `owl next` → `action.kind: "skip_conditional_step" {task_id, step_id, reason}`.
- `owl step skip TASK-ID STEP-ID --reason condition_unmet` — без изменений (используется).
- Ruby: `Owl::Workflows::Internal::ConditionEvaluator.evaluate(root:, task_id:, predicate:)`;
  классификатор ready-steps (в `Workflows::Api`/`Tasks::Api`) вызывает его; вынести в
  `next_action_resolver` новый кейс.
