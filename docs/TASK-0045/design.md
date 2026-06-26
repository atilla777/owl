---
status: shipped
summary: >-
  Единая внутренняя проекция элемента списка задач (task_id + общее ядро полей),
  применяемая в available/ready/list на уровне вывода. On-disk index.yaml (ключ
  id) не меняется — переименование только при сериализации. Ломающее → major bump.
---

# Context

Три команды строят элементы списка задач независимо:

- `Tasks::Api.list` → `Backends::Filesystem#list` отдаёт **сырые записи
  `tasks/index.yaml`** (`tasks:`), у которых ключ идентичности — `id`
  (это on-disk поле индекса). Несёт tracker-поля: `id, title, workflow,
  kind, parent_id, priority, created_at, status, labels, blocked_by,
  archived_at`.
- `Tasks::Api.ready` → `Internal::ReadyScanner.scan` фильтрует те же сырые
  записи индекса и тоже отдаёт их с ключом `id`.
- `Tasks::Api.available` → `Backends::Filesystem#available` (и
  `Internal::ReadyAvailabilityScanner` для `--dep-aware`) строит отдельный
  `candidate_hash` с ключом `task_id` и полями `task_id, title, kind,
  priority, created_at, ready_step_ids, reason` — **без** `status`/`workflow`.

Корень расхождения: `ready`/`list` сериализуют сырую запись индекса как есть
(ключ `id`), а `available` строит собственный хэш (ключ `task_id`). Нет
единого места, описывающего форму элемента, поэтому контракты разъехались и
будут разъезжаться дальше.

Ключевое ограничение: **`tasks/index.yaml` хранит `id`** — это формат
хранения, его трогать нельзя (отдельное, не заявленное здесь ломающее
изменение). Переименование `id`→`task_id` должно происходить **только на
выходе** (проекция перед сериализацией), не в хранилище.

# Decision

Ввести единую внутреннюю проекцию `Tasks::Internal::TaskSummary` —
единственный источник истины для формы элемента списка задач:

```
Tasks::Internal::TaskSummary.project(entry, extra: {})
# entry — сырая запись индекса (ключ 'id')
# → Hash с каноничным порядком ключей:
#   task_id  (из entry['id'])
#   title, kind, priority, created_at, status, workflow   # общее ядро
#   *extra (поля конкретной команды, поверх ядра)
```

Применение:

- **`list`** и **`ready`**: каждую сырую запись индекса прогнать через
  `TaskSummary.project(entry, extra: tracker_extra(entry))`, где
  `tracker_extra` = `{ parent_id, labels, blocked_by, archived_at }`.
  Ключ `id` в выводе исчезает, появляется `task_id`; tracker-поля
  сохраняются поверх ядра. Top-level контейнеры (`tasks:` / `ready:`) не
  меняются.
- **`available`** (обе ветки — обычная и `--dep-aware`): `candidate_hash`
  переписать через `TaskSummary.project(entry, extra: { ready_step_ids:,
  reason: })`. Это **добавляет** в `available` отсутствовавшие core-поля
  `status` и `workflow` (читаются из той же записи индекса `entry`).

Итоговый общий core во всех трёх: `task_id, title, kind, priority,
created_at, status, workflow`. Специфика: `available` → `ready_step_ids,
reason`; `ready`/`list` → `parent_id, labels, blocked_by, archived_at`.

Слой размещения: `Tasks::Internal` (проекция — внутренняя деталь), вызовы
из `Backends::Filesystem#list/#available`, `Internal::ReadyScanner`,
`Internal::ReadyAvailabilityScanner`. `api.rb` остаётся тонким делегатом
(сохраняем 100% coverage публичного слоя).

Версия: **major bump** `Owl::VERSION` + запись в `CHANGELOG.md` в том же
коммите (ломающее изменение JSON-контракта `ready`/`list`).

# Alternatives

1. **Дуальный ключ `task_id`+`id` (additive, minor).** Оба ключа в выводе
   на «переходный период». Отвергнуто: инструмент контролирует своих
   потребителей, переходный период не заканчивается, мусор остаётся
   навсегда. Решение пользователя 2026-06-26.
2. **Стандартизация на `id` вместо `task_id` (major).** Переписать
   `available`/`next` на `id`. Меняет меньше call-site'ов, но противоречит
   формулировке тайтла и менее однозначно во вложенных контекстах (рядом
   `parent_id`/`step_id`). Отвергнуто.
3. **Точечный фикс в каждой команде без общей проекции.** Переименовать
   ключ и дописать поля по месту в трёх местах. Отвергнуто: дублирует
   контракт в трёх точках — ровно та причина, по которой формы разъехались;
   снова разъедутся. Общая проекция — суть рефактора.
4. **Менять ключ в самом `index.yaml`.** Отвергнуто: ломает формат
   хранения (отдельное, не заявленное изменение); проекция на выводе
   полностью решает задачу без миграции данных.

# Risks

- **Ломающее изменение для потребителей.** `ready`/`list` меняют ключ.
  Митигировать: обновить всех in-repo потребителей (`owl-*` скиллы,
  orchestrator, код `lib/owl`, читающий `id` из этих выводов), major bump,
  явная запись в `CHANGELOG.md`. Consumer-проекты подхватят через
  `owl upgrade`.
- **Случайное изменение формата хранения.** Проекция обязана быть только
  на выводе; запись индекса (`TaskWriter`, `id`-ключ) не трогаем. Покрыть
  тестом, что `index.yaml` по-прежнему содержит `id`.
- **`--dep-aware` ветка.** `ReadyAvailabilityScanner` легко забыть —
  должна идти через ту же проекцию. Явный AC + spec.
- **Потеря/смена семантики полей.** Имена и значения core-полей должны
  совпадать побайтно между командами; available впервые получает
  `status`/`workflow` — проверить, что они присутствуют и непустые для
  обычных задач.
- **Published JSON-schema.** Если есть `schemas/task*.json`, описывающий
  эти выводы, синхронизировать в том же коммите.
- **100% line coverage** `lib/owl/**/api.rb` — сохранить.

# API

Публичный CLI/JSON-контракт после рефактора. Элемент списка задач во всех
трёх командах разделяет общее ядро (порядок ключей каноничен):

Общее ядро (во всех трёх):

```json
{
  "task_id":    "TASK-0045",
  "title":      "…",
  "kind":       "task",
  "priority":   6,
  "created_at": "2026-06-26T14:56:16Z",
  "status":     "open",
  "workflow":   "refactor"
}
```

`owl task available --json` (и `--dep-aware`) — ядро + ranking:

```json
{ "ok": true, "available": [ { …core…,
  "ready_step_ids": ["brief"], "reason": "priority=6; oldest ready task" } ] }
```

`owl task ready --json` — ядро + tracker:

```json
{ "ok": true, "ready": [ { …core…,
  "parent_id": null, "labels": [], "blocked_by": [], "archived_at": null } ] }
```

`owl task list --json` — ядро + tracker, плюс существующие top-level
`index_path`, `schema_version`:

```json
{ "ok": true, "index_path": "…", "schema_version": 1,
  "tasks": [ { …core…,
    "parent_id": null, "labels": [], "blocked_by": [], "archived_at": null } ] }
```

Вне охвата (не меняются): `owl next`, `owl task ready-steps`,
`owl task aggregate-status` (там `task_id` — ссылка на задачу, не
задача-объект); top-level имена массивов (`available`/`ready`/`tasks`);
on-disk `tasks/index.yaml` (ключ `id`).
