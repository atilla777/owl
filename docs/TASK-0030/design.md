---
status: shipped
summary: "Авто-выбор задачи (две точки: TaskResolver.auto_select И ClaimService.claim_next) должен быть пересечением available-кандидатов (есть готовый шаг, не заклеймлено) с deps+status-гейтом (blocked_by завершены, статус не on_hold/blocked/terminal). available остаётся dependency-blind."
---

# Context

Авто-выбор задачи происходит в ДВУХ местах, и оба сегодня dependency-blind:

1. **`TaskResolver.auto_select`** (`lib/owl/orchestration/internal/task_resolver.rb`) —
   read-only хвост лестницы `explicit → current_pointer → auto_select` для
   `owl next`/`owl instructions`. Зовёт `Tasks::Api.available`.
2. **`ClaimService.claim_next`** (`lib/owl/tasks/internal/claim_service.rb:83`) —
   мутирующий путь `owl task claim --next`. Тоже зовёт `AvailabilityScanner.scan`
   напрямую и клеймит первого кандидата.

**Ключевое уточнение по сканерам (проверено в коде):**

- `AvailabilityScanner` (`availability_scanner.rb`) фильтрует кандидатов по тому, что
  у задачи **есть хотя бы один диспетчеризуемый workflow-шаг** (`ready_step_ids` через
  `Workflows::Api.ready_steps`) И нет живого claim. Но **игнорирует** `blocked_by` и
  task-level `status`. Несёт `reason`, `ready_step_ids`. Сортировка `[-priority,
  created_at, id]`.
- `ReadyScanner` (`ready_scanner.rb`, TASK-0026) фильтрует по **deps complete**
  (`blocked_by` все done/archived) + **status non-terminal** (`done|archived|abandoned`)
  + нет живого claim. Но **НЕ проверяет**, есть ли готовый workflow-шаг. Та же сортировка.

То есть наборы **НЕ** subset/superset: каждый сканер несёт фильтр, которого нет у
другого. Наивная замена `available → ready` потеряла бы фильтр «есть готовый шаг» и
могла бы авто-выбрать задачу без диспетчеризуемого шага (регрессия). Нужен **AND обоих
условий**.

Дополнительно `ReadyScanner` пока не исключает `on_hold`/`blocked` (их нет в
TERMINAL_STATUSES), а brief требует их пропускать.

# Decision

1. **Пересечение, не замена.** Кандидат для авто-выбора/авто-claim = задача, которая
   `available` (есть готовый шаг, не заклеймлена) **И** проходит deps+status-гейт
   (`blocked_by` завершены, статус рабочий). Реализуем как фильтр available-кандидатов
   по множеству id из deps+status-aware скана. Порядок берём от available (та же
   сортировка), `reason`/`ready_step_ids` сохраняются.

2. **Единый источник deps+status-гейта.** Расширяем `ReadyScanner`: вводим
   `NON_READY_STATUSES = TERMINAL_STATUSES + %w[on_hold blocked]` и используем его в
   `ready_entry?` для проверки собственного статуса (deps-логика без изменений).
   Множество id из `ReadyScanner` = «задачи, которые не заблокированы и в рабочем
   статусе». Side-effect (желательный): `owl task ready` тоже перестаёт показывать
   `on_hold`/`blocked` — корректно для ready-work-набора (как beads `bd ready`).
   Зафиксировать в CHANGELOG.

3. **Общая точка пересечения — в tasks-слое.** Чтобы не дублировать логику в backend
   (`ClaimService`) и orchestration (`TaskResolver`), добавляем внутренний
   `Owl::Tasks::Internal::ReadyAvailabilityScanner` (имя по вкусу) или хелпер,
   который: берёт `AvailabilityScanner` кандидатов, пересекает с id-множеством
   deps+status-скана, возвращает отфильтрованный список в том же формате, что
   `available` (`{ task_id, priority, reason, ready_step_ids, … }`). Экспонируем
   через `Owl::Tasks::Api` (напр. `available(root:, dep_aware: false)` с новым
   keyword, дефолт `false` = текущее dep-blind поведение). Тогда:
   - `ClaimService.claim_next` зовёт dep-aware вариант;
   - `TaskResolver.auto_select` зовёт dep-aware вариант (через Api, без обращения в
     tasks/internal напрямую — слой соблюдён).

4. **available по умолчанию неизменен.** `owl task available` и
   `Tasks::Api.available` (без `dep_aware:`/с `dep_aware: false`) остаются
   dependency-blind — докстринг и существующие тесты в силе. Регрессионный тест:
   dep-заблокированная/`on_hold` задача всё ещё в дефолтном `available`.

5. **explicit / current_pointer не трогаем.** Пользователь вправе вручную вести
   заблокированную/отложенную задачу через явный TASK-ID или current-указатель.

# Alternatives

- **Заменить available на ready целиком.** Теряет фильтр «есть готовый шаг» → может
  выбрать задачу без диспетчеризуемого шага. Отклонено (регрессия).
- **Сделать сам AvailabilityScanner deps-aware.** Сломало бы контракт
  `owl task available` (докстринг обещает dependency-blind) и его тесты. Отклонено;
  вместо этого dep-aware — opt-in keyword.
- **Дублировать фильтр в ClaimService и TaskResolver по отдельности.** Две копии
  правила «готово к работе». Отклонено в пользу общего tasks-слой хелпера.
- **Фильтровать только в orchestration (TaskResolver), не трогая claim_next.**
  Оставило бы `owl task claim --next` способным заклеймить заблокированную задачу —
  brief явно называет `claim --next`. Отклонено; правим обе точки.

# Risks

- **Два call-site.** Нужно покрыть обе точки (`claim_next`, `auto_select`) тестами,
  иначе одна останется dep-blind. Митигировано общим хелпером + тестами на оба пути.
- **Изменение `owl task ready`-вывода** (скрывает `on_hold`/`blocked`) — minor bump +
  явная строка CHANGELOG. Низкий риск.
- **Покрытие api.rb.** Новый keyword в `Tasks::Api.available` (или новый Api-метод) —
  100% покрытие обоих веток (`dep_aware: true|false`).
- **reason/shape.** dep-aware вариант сохраняет формат available-кандидата
  (`reason`, `ready_step_ids`), чтобы потребители (claim_first_available читает
  `candidate[:task_id]`; resolver читает `reason`) не сломались.

# API

- **CLI:** без новых команд/флагов. `owl next`/`owl instructions` авто-выбор и
  `owl task claim --next` становятся deps+status-aware. `owl task ready` перестаёт
  показывать `on_hold`/`blocked`. `owl task available` — без изменений (dep-blind).
- **Ruby:**
  - `Owl::Tasks::Api.available(root:, dep_aware: false)` — новый keyword; `true`
    пересекает available-кандидатов с deps+status-aware ready-множеством. Дефолт
    `false` сохраняет текущий контракт. (Либо отдельный метод `available_dep_aware`;
    выбрать при реализации по чистоте/покрытию.)
  - `Owl::Tasks::Internal::ReadyScanner` — `ready_entry?` исключает также
    `on_hold`/`blocked` (`NON_READY_STATUSES`).
  - Новый внутренний хелпер пересечения (available ∩ ready-ids).
  - `Owl::Tasks::Internal::ClaimService.claim_next` — зовёт dep-aware скан.
  - `Owl::Orchestration::Internal::TaskResolver.auto_select` — зовёт dep-aware
    `Tasks::Api.available(dep_aware: true)`; reason берётся от кандидата.
