---
status: shipped
summary: "AvailabilityScanner: ready_step_ids → actionable_step_ids = value[:ready] ids ∪ value[:conditional_skip] ids (один вызов ready_steps). build_candidate гейтит по actionable; candidate_hash несёт actionable в ready_step_ids. Conditional-only задача становится available; deps-пересечение и ready-задачи без изменений."
---

# Context

`AvailabilityScanner.build_candidate` гейтит доступность по `ready_step_ids(root,
task_id)`, где:
```
def ready_step_ids(root:, task_id:)
  result = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
  return [] if result.err?
  Array(result.value[:ready]).map { |step| step[:id] }
end
```
`return nil if ready_ids.empty?` отбрасывает задачу. Но `ready_steps` возвращает и
`conditional_skip: [{ id:, reason: }]` (TASK-0028) — шаги с ложным `when:`, которые
`next_action_resolver` продвигает через `skip_conditional_step` ПЕРЕД `ready`. Значит
задача с только conditional_skip продвигаема, но auto-select её теряет.

# Decision

Расширить гейт доступности с `ready` до **actionable = ready ∪ conditional_skip**,
используя ОДИН вызов `ready_steps` (оба bucket'а из одного результата):
```
def actionable_step_ids(root:, task_id:)
  result = Owl::Workflows::Api.ready_steps(root: root, task_id: task_id)
  return [] if result.err?
  ready = Array(result.value[:ready]).map { |s| s[:id] }
  conditional = Array(result.value[:conditional_skip]).map { |s| s[:id] }
  ready + conditional
end
```
- `build_candidate`: `actionable = actionable_step_ids(...); return nil if
  actionable.empty?`.
- `candidate_hash`: класть `ready_step_ids: actionable` (поле = «шаги, по которым
  задача продвигаема сейчас»: dispatch или auto-skip). Имя поля историческое;
  потребители (`claim_service`) читают только `:task_id`, так что расширение
  содержимого безопасно.
- `blocked_by_children` / `awaiting_plan_approval` НЕ включаются (ожидание, не
  действие) — задача в этих состояниях остаётся недоступной, как сейчас.

`ReadyAvailabilityScanner` (deps-пересечение, TASK-0030) не меняется: он пересекает
available-кандидатов с deps+status-ready set; conditional-only задача теперь в
available и, если её deps/status ок, остаётся в пересечении. `next_action_resolver`
уже умеет conditional_skip → действий не требует.

# Alternatives

- **Включать conditional ids в отдельное поле, гейт по сумме.** Лишнее поле в
  candidate_hash без потребителя. Достаточно расширить смысл `ready_step_ids` до
  actionable. Отклонено как избыточное.
- **Чинить в next_action_resolver/TaskResolver, не в AvailabilityScanner.** Резолвер
  уже корректен (conditional → skip action); проблема именно в том, что задача не
  попадает в available set. Чинить надо в сканере доступности.
- **Включать blocked_by_children/awaiting_plan как actionable.** Это ожидание, не
  немедленное действие — задача не должна авто-выбираться, пока ждёт детей/план.
  Отклонено.
- **Второй вызов ready_steps для conditional.** Лишний проход; берём оба bucket'а из
  одного результата. Отклонено.

# Risks

- **Регрессия ready-задач.** Для задач с `ready` шагом actionable ⊇ ready, гейт
  `empty?` даёт тот же результат; сортировка/кандидаты не меняются. Полный rspec —
  контроль.
- **Семантика поля ready_step_ids.** Теперь включает conditional ids. Internal-поле,
  потребители читают `:task_id`; задокументировать в комментарии candidate_hash.
- **Покрытие.** `availability_scanner.rb` — internal; `tasks/api.rb#available` покрыт.
  Добавить тест на conditional-only available.

# API

- **CLI/JSON:** `owl task available` и авто-выбор (`owl next`/`claim --next`) теперь
  включают conditional-only задачу. Контракт полей не ломается.
- **Ruby (internal):** `AvailabilityScanner.ready_step_ids` → `actionable_step_ids`
  (ready ∪ conditional_skip); `build_candidate`/`candidate_hash` используют actionable.
