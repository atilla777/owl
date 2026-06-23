---
status: shipped
summary: >-
  Fix-forward «aggregate видит архив». (1) ArchiveReader/`Owl::Archive::Api.list`
  выставляют `parent_id` (читается из архивного task.yaml — entry_summary уже его
  читает ради title). (2) `Owl::Tasks::Internal::ChildrenLister` мёржит детей из
  активного индекса И из archive-роли (через публичную границу
  `Owl::Archive::Api.list`, фильтр по parent_id), дедуп по task_id. Архивный
  ребёнок несёт `status: 'archived'`, который `AggregateStatus.child_state` уже
  маппит в state `archived` → all-archived → aggregate `done` → гейт
  `children_complete` открывается. Пустой набор (детей не было) по-прежнему
  'open'. (3) Одноразовая реконсиляция TASK-0015. Версия — patch (additive
  parent_id, back-compat).
---

# Design — Composite gate bug fix (aggregate учитывает архивных детей)

## Context

Слои и текущие точки:

- `Owl::Tasks::Internal::ChildrenLister.call(root:, parent_id:)`
  (`children_lister.rb`) читает `tasks/index.yaml` (`IndexReader`) и выбирает
  записи с `parent_id == PARENT`. Архивный ребёнок из индекса исчез → пусто.
- `Owl::Tasks::Internal::AggregateStatus` (`aggregate_status.rb`):
  - `child_state` уже маппит `status == 'archived'` → `'archived'` (строка 53);
  - `aggregate_state`: `'open' if by_child.empty?` (67), `'done' if all archived`
    (69), `'ready' if all done/archived` (70). Логика верна — проблема лишь в
    том, что архивные дети не доходят до `by_child`.
- `Owl::Archive::Internal::ArchiveReader` (`archive_reader.rb`) перечисляет архив
  через `Owl::Storage::Api` (слой соблюдён, без прямого FS). `entry_summary`
  **уже читает** архивный `task.yaml` (берёт `title`), но `parent_id` наружу не
  выставляет. `Owl::Archive::Api` = `archive_task/list/show/read`.
- Архивный `task.yaml` ребёнка содержит `parent_id` (подтверждено: TASK-0018 →
  `parent_id: TASK-0015`).
- Cross-domain: `Tasks::Internal` сейчас НЕ зависит от `Owl::Archive`
  (`tasks/internal/archive/*` — это другой, внутренний подмодуль Tasks).
  `Archive::Api` зависит только от config/storage → ребро `Tasks → Archive::Api`
  ацикличное.

`brief` зафиксировал: fix-forward «aggregate видит архив» (не превенция
self-archive); реконсиляция TASK-0015; без ложных открытий для бездетного
родителя.

## Decision

### 1. Выставить `parent_id` из архива (`Owl::Archive`)

- `ArchiveReader.entry_summary` (и, по желанию, `show`) добавляют `parent_id`,
  читая архивный `task.yaml`. Чтобы не читать yaml дважды, прочитать payload
  один раз и взять `title` + `parent_id` из него.
- `Owl::Archive::Api.list(root:)` теперь возвращает в каждом элементе
  `parent_id` (additive поле; форма не ломается). Это заодно закрывает разрыв
  «archive list/show не показывают parent_id».

### 2. ChildrenLister мёржит индекс + архив

`Owl::Tasks::Internal::ChildrenLister.call(root:, parent_id:)`:

- как раньше — дети из `tasks/index.yaml` по `parent_id`;
- **плюс** архивные дети: `Owl::Archive::Api.list(root:)` →
  `select { |a| a[:parent_id] == parent_id }`, смаппить в child-summary
  `{ id:, title:, workflow_key:, status: 'archived', kind:, ... }` (как
  `base_summary`, но `status: 'archived'`);
- **дедуп по `task_id`**: если задача почему-то и в индексе, и в архиве —
  предпочесть архивную (терминальное состояние);
- порядок/форма результата прежние (`enrich`/`progress` сохранить; для архивных
  прогресс читается из архивного payload, либо помечается архивным — детально в
  plan).

Вызов идёт через ПУБЛИЧНУЮ границу `Owl::Archive::Api` (не `Archive::Internal`) —
корректный cross-domain паттерн (docs/agents/27).

### 3. AggregateStatus — без изменения логики

`child_state` для архивного ребёнка (через index-entry `status: 'archived'`)
вернёт `'archived'`; `aggregate_state` для all-archived → `'done'`. Пустой
`by_child` (детей нет ни в индексе, ни в архиве) → `'open'` (ложного открытия
нет). Возможна правка `child_state`, чтобы для архивной записи не пытаться
читать активный `task.yaml` (его уже нет) — вернуть `'archived'` сразу по
`status`. (Сейчас строка 53 это и делает — проверить, что архивная запись
несёт `status: 'archived'`.)

### 4. Реконсиляция TASK-0015 (одноразовая, в поставке)

После фикса `owl task aggregate-status TASK-0015` → `done` (ребёнок TASK-0018
архивен). TASK-0015 физически уже в архиве; нужно лишь закрыть bookkeeping:
гейт открыт → довести шаги `archive` и `commit_push` до `done`
(`owl step start/complete`). Это операция доставки (orchestrator), не код гема;
зафиксировать в `verification.md`. Идемпотентно (если уже done — no-op).

### 5. Версия

Тронуты `lib/owl/archive/**` и `lib/owl/tasks/**` → **patch**-бамп `Owl::VERSION`
+ `CHANGELOG.md` тем же коммитом. Изменение back-compat: `parent_id` —
additive поле; `by_child` лишь полнее; форма JSON `aggregate-status`/`list`/
`ready-steps` не ломается.

## Alternatives

- **Запретить self-archive ребёнку под composite-родителем.** Отвергнуто в brief:
  меняет lifecycle ребёнка (plain feature/refactor workflow не знает, что он
  ребёнок); fix-forward проще и не трогает рабочие процессы.
- **`aggregate_state` empty→'done'.** Неверно: бездетный (не декомпозированный)
  родитель ложно открыл бы гейт. Нужно именно «видеть архивных детей».
- **Сканировать `tasks/archive` напрямую в ChildrenLister.** Отвергнуто:
  нарушает слой/инвариант FS; идём через `Owl::Archive::Api`.
- **`owl task index rebuild` включает архив.** Отвергнуто: индекс — для активных
  задач; раздувание архивом неуместно.
- **Дать parent_id только через новый метод `Archive::Api.children_of`.**
  Допустимо, но `list`+`parent_id` проще и переиспользуемо; выбран additive
  `parent_id` в `list`.

## Risks

- **Цикл require `Tasks → Archive::Api`.** Митигация: проверено — Archive не
  зависит от Tasks; ребро ацикличное. Прогон полного suite ловит регресс
  require.
- **Производительность:** `Archive::Api.list` читает каждый архивный task.yaml;
  на каждый aggregate-вызов скан архива. На текущем масштабе (десятки) дёшево;
  отметить как будущую оптимизацию (кэш/индекс архива).
- **child_state для архивной записи** не должен пытаться читать отсутствующий
  активный `task.yaml`. Митигация: архивная запись несёт `status: 'archived'`,
  строка 53 раннего возврата; спека на это.
- **Дубли/старый формат** (архив без parent_id). Митигация: nil parent_id →
  не ребёнок; дедуп по task_id.
- **Реконсиляция TASK-0015** — разовая ручная операция; держать идемпотентной и
  зафиксировать команды в verification.
- **Контракт `aggregate-status`.** Форма не меняется (доп. записи/поле). Не-
  composite не затронут.

## API

**Ruby (additive):**

```
Owl::Archive::Api.list(root:)
  => Result.ok(archived: [{ task_id:, slug:, archived_date:, title:, path:,
                            parent_id: }, ...])   # + parent_id (additive)

Owl::Tasks::Internal::ChildrenLister.call(root:, parent_id:)
  => Result.ok(parent_id:, children: [ {id:, title:, status:, ...}, ... ])
     # children = индекс ∪ архив (по parent_id), дедуп по task_id;
     # архивный ребёнок: status: 'archived'
```

**CLI (форма не меняется, значения точнее):**

```
owl task aggregate-status PARENT --json
  => { aggregate: 'done', by_child: [ {id, state:'archived', status:'archived'} ] }
     # для родителя, все дети которого архивны (раньше: aggregate:'open', by_child:[])
owl task ready-steps PARENT --json   # archive/commit_push → ready (гейт открыт)
owl archive list --json              # элементы теперь содержат parent_id
```

**Новые/изменённые тесты:** `spec/owl/tasks/aggregate_status_archived_children_spec.rb`
(wedge-сценарий: единственный ребёнок архивен → aggregate 'done' / гейт открыт;
смешанные дети; бездетный родитель → 'open'); spec на `Archive::Api.list`
parent_id; spec на `ChildrenLister` мёрж индекс+архив с дедупом.
