---
status: shipped
summary: >-
  Терминальная задача защищается на двух уровнях: AbandonWriter переиспользует
  CurrentResetter (паритет с delete), а слой оркестрации/CLI отличает явный
  доступ (reject через task_terminal) от неявного резолва из current-указателя
  (тихий fallback в auto_select). Задачный TERMINAL_STATUSES выносится в один
  общий модуль, переиспользуемый availability/ready-сканерами.
---

# Context

`status: abandoned`/`archived`/`done` — терминальные статусы задачи, но защита
от «протекания» мёртвой задачи в оркестрацию неполна и неединообразна (см.
brief). Три независимых дефекта:

1. `AbandonWriter` (`lib/owl/tasks/internal/abandon_writer.rb`) снимает claim
   (`Archive::ClaimResetter`), но не очищает current-указатель — в отличие от
   `Deleter`, который с TASK-0041 использует `Archive::CurrentResetter.reset_if_matches`.
2. `TaskResolver.from_current` (`lib/owl/orchestration/internal/task_resolver.rb`)
   возвращает id из current-указателя без проверки статуса, поэтому `owl next`
   советует `dispatch_step` по терминальной задаче.
3. `TERMINAL_STATUSES` для задачного уровня продублирован в `availability_scanner`
   (`%w[archived abandoned done]`) и `ready_scanner` (`%w[done archived abandoned]`).

# Decision

**Двухуровневая защита + единый источник истины.**

1. **abandon чистит указатель.** В `AbandonWriter.persist` (после успешного
   rebuild индекса, рядом с `ClaimResetter.delete_if_present`) вызвать
   `Archive::CurrentResetter.reset_if_matches(local_state_root:, task_id:)`.
   Идемпотентная ветка early-return для уже-abandoned задачи тоже должна пройти
   через очистку указателя (вынести reset до early-return либо выполнять в обеих
   ветках), чтобы повторный abandon чинил протухший указатель.

2. **Явный доступ к терминальной задаче → `task_terminal`.** Ввести общую
   проверку в слое оркестрации/Api для `next` / `ready-steps` / `status` /
   `instructions`: когда TASK-ID получен **явно** (источник resolve = `explicit`)
   и статус задачи терминальный — вернуть `Result.err(code: :task_terminal, …)`.
   Для `next` это значит: проверка применяется к ветке `explicit(task_id)`, но
   НЕ к ветке `from_current`.

3. **Неявный терминальный указатель в `next` → fallback.** В
   `TaskResolver.from_current`: если задача из current-указателя терминальна,
   не возвращать её, а провалиться в `auto_select(root:)` (как при отсутствии
   указателя). Это тихий путь без ошибки.

4. **Единый `TERMINAL_STATUSES`.** Вынести задачную константу
   (`%w[archived abandoned done]`) в один общий модуль (напр.
   `Owl::Tasks::Internal::TaskStatuses::TERMINAL`), переиспользовать в
   `availability_scanner` и `ready_scanner`; шаговый `completion_gate`
   (`%w[done skipped]`) остаётся отдельным (это статусы шагов, иное понятие).

Статус задачи для проверок читается через существующий слой
`Tasks::Api`/`TaskReader`, без прямого FS-доступа из оркестрации.

# Alternatives

- **A. Жёсткий reject везде (в т.ч. для `from_current`).** Любой терминальный
  резолв — ошибка, без fallback. Отклонено: ломает эргономику `owl next` без
  аргумента, заставляя человека руками чистить указатель на редком legacy-пути.
- **B. Тихий fallback везде (в т.ч. для явного id).** Молча подменять явно
  названную терминальную задачу другой. Отклонено: сюрприз для пользователя,
  спросившего про конкретную задачу; противоречит формулировке «reject» в
  заголовке.
- **C. Не чистить указатель в abandon, лечить только в резолвере.** Отклонено:
  оставляет видимое расхождение `owl task current` ↔ реальность и расходится с
  поведением `delete`; чистка указателя — корень проблемы.
- **D. Не объединять TERMINAL_STATUSES.** Отклонено: дубликаты уже разошлись по
  порядку; явная цель задачи — один источник истины.

# Risks

- **Совместимость JSON-контракта.** Новый код ошибки `task_terminal` для
  явного доступа к терминальной задаче — это смена реакции команд, ранее
  «притворявшихся», что задача жива. Потенциально мажорное изменение контракта;
  версия уточняется на шаге plan (вероятно minor, т.к. добавляется новый код
  ошибки на ранее-некорректном пути, а не ломается успешный ответ).
- **Идемпотентный abandon.** Риск пропустить очистку указателя в early-return
  ветке — явно покрывается тестом «повторный abandon чинит протухший указатель».
- **Регрессия архивации.** Объединять ТОЛЬКО задачный `TERMINAL_STATUSES`;
  шаговый `completion_gate` не трогать, иначе можно сломать гейт архивации.
- **`instructions`/`status` без явного id.** Уточнить источник id: применять
  reject только когда id действительно передан явно, а не разрешён из указателя,
  иначе сломаем неявные вызовы.

# API

Изменения поведения CLI (публикуется в `docs/`):

- `owl task abandon TASK-X` — теперь сайд-эффектом очищает current-указатель,
  если он указывал на TASK-X (паритет с `owl task delete`). JSON-ответ успеха
  без изменений по форме.
- `owl next TASK-X` / `owl status TASK-X` / `owl task ready-steps TASK-X` /
  `owl instructions TASK-X` с **явным** терминальным id →
  `{ ok: false, error: { code: "task_terminal", … } }` + ненулевой exit-код.
- `owl next` (без аргумента) с терминальным current-указателем → игнорирует
  указатель, отдаёт `dispatch_step` следующей доступной задачи либо
  `no_available_task`.
- Внутренняя константа: `Owl::Tasks::Internal::TaskStatuses::TERMINAL`
  (`%w[archived abandoned done]`) как единый источник истины для задачного
  терминального статуса.
