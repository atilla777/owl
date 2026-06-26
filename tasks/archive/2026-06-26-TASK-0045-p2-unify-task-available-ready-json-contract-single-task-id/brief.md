---
status: approved
summary: >-
  Унифицировать JSON-контракт команд owl task available/ready/list: единый ключ
  идентичности task_id вместо разнобоя id/task_id и общий набор core-полей с
  одинаковыми именами и семантикой. Ломающее изменение JSON-контракта → major bump.
---

# Problem

Три команды, выдающие списки задач-объектов, отдают несогласованный JSON:

| Команда            | ключ id      | top-level | специфичные поля                                              |
| ------------------ | ------------ | --------- | ------------------------------------------------------------ |
| `owl task available` | `task_id`  | `available` | `ready_step_ids`, `reason`                                  |
| `owl task ready`     | `id`       | `ready`     | `workflow`, `status`, `labels`, `blocked_by`, `parent_id`, `archived_at` |
| `owl task list`      | `id`       | `tasks`     | те же tracker-поля, что и `ready`                            |

Расхождения:

1. **Ключ идентичности задачи различается** — `task_id` в `available`,
   но `id` в `ready`/`list`. Потребитель (orchestrator, `owl-*` скиллы,
   consumer-проекты) вынужден знать, какую команду он вызвал, чтобы достать
   идентификатор задачи из элемента списка.
2. **Нет общего ядра полей** — `available` несёт ranking-поля
   (`ready_step_ids`, `reason`), но не несёт базовых tracker-полей
   (`status`, `workflow`, `priority` есть, но `status`/`workflow` нет);
   `ready`/`list` несут tracker-поля, но не несут `ready_step_ids`. Одни
   и те же концептуальные атрибуты задачи (идентичность, заголовок, тип,
   приоритет, дата создания, статус, workflow) выражены по-разному или
   отсутствуют в зависимости от команды.

Это health-review-находка (label `health-review-2026-06-26`). Контракт
CLI/JSON — публичный (Конституция §7.1), его непоследовательность создаёт
лишнюю когнитивную нагрузку и баг-почву в каждом потребителе.

# Goal

Свести `owl task available`, `owl task ready`, `owl task list` к единому
JSON-контракту:

- **единый ключ идентичности `task_id`** во всех трёх командах (вместо
  `id`/`task_id`);
- **общий набор core-полей** с одинаковыми именами и семантикой,
  присутствующий в элементе списка каждой из трёх команд;
- **специфичные поля** каждой команды сохраняются поверх общего ядра
  (`available` → `ready_step_ids`, `reason`; `ready`/`list` → `labels`,
  `blocked_by`, `archived_at` и т.п.).

Направление унификации — на `task_id` (по формулировке тайтла и ради
однозначности ключа в любом вложенном контексте, где рядом есть
`parent_id`/`step_id`). Это **ломающее** изменение JSON-контракта
`ready`/`list` → требует **major bump** `Owl::VERSION` и записи в
`CHANGELOG.md` в том же коммите. Дуальный ключ (`task_id`+`id`) отвергнут
сознательно: «переходный период» в инструменте, контролирующем своих
потребителей, не заканчивается и оставляет мусор навсегда.

# Scenarios

### Requirement: Единый ключ идентичности task_id

The system SHALL emit the task identity under the key `task_id` (not `id`)
in every list element returned by `owl task available`, `owl task ready`,
and `owl task list`.

#### Scenario: ready использует task_id

- WHEN пользователь выполняет `owl task ready --json`
- THEN каждый элемент массива `ready` содержит ключ `task_id` со значением
  идентификатора задачи
- AND ни один элемент не содержит ключа `id` как идентификатора задачи

#### Scenario: list использует task_id

- WHEN пользователь выполняет `owl task list --json`
- THEN каждый элемент массива `tasks` содержит ключ `task_id`
- AND ни один элемент не содержит ключа `id` как идентификатора задачи

#### Scenario: available сохраняет task_id

- WHEN пользователь выполняет `owl task available --json`
- THEN каждый элемент массива `available` содержит ключ `task_id`
  (как и прежде)

### Requirement: Общее ядро полей

The system SHALL include an identical set of core fields — `task_id`,
`title`, `kind`, `priority`, `created_at`, `status`, `workflow` — with the
same names and semantics in every list element of all three commands.

#### Scenario: core-поля во всех трёх командах

- WHEN пользователь выполняет любую из `owl task available|ready|list --json`
- THEN каждый элемент списка содержит все core-поля `task_id`, `title`,
  `kind`, `priority`, `created_at`, `status`, `workflow`
- AND имена и семантика этих полей одинаковы между командами

#### Scenario: специфичные поля сохраняются поверх ядра

- WHEN пользователь выполняет `owl task available --json`
- THEN элемент дополнительно содержит специфичные поля `ready_step_ids` и
  `reason`
- AND core-поля не теряются

### Requirement: Сигнализация ломающего изменения

The system SHALL ship the breaking JSON-contract change with a major
`Owl::VERSION` bump and a matching `CHANGELOG.md` entry in the same commit.

#### Scenario: major bump и changelog

- WHEN изменение контракта `ready`/`list` смержено
- THEN `Owl::VERSION` повышен по major (X.0.0)
- AND `CHANGELOG.md` содержит запись с описанием ломающего изменения ключа
  `id`→`task_id`

### Requirement: Согласованность потребителей в репозитории

The system SHALL update every in-repo consumer of the renamed key
(`owl-*` skills, orchestrator, internal callers) so that no consumer reads
`id` as the task identity from `available`/`ready`/`list`.

#### Scenario: скиллы и orchestrator читают task_id

- WHEN после рефактора orchestrator/скиллы выбирают задачу из вывода
  `task available`/`ready`/`list`
- THEN они читают идентификатор из ключа `task_id`
- AND ни один внутренний потребитель не падает на отсутствии ключа `id`

# Edge cases

- **Связь с TASK-0041 (ready/available overlap).** TASK-0041 решает
  *семантику* (какие задачи попадают в `ready` vs `available`); эта задача —
  *форму* JSON (ключи/core-поля). Слои ортогональны, выполняем независимо.
  Если TASK-0041 поедет первой и сольёт/изменит наборы задач, контракт из
  этого брифа всё равно применим к результирующему выводу.
- **`dep_aware`-ветка `available`.** `owl task available --dep-aware`
  (ReadyAvailabilityScanner) должна отдавать тот же унифицированный контракт,
  что и обычная ветка `available`.
- **Композитные/дочерние задачи.** Элементы с `parent_id`/`kind != task`
  обязаны нести то же общее ядро; `parent_id` остаётся как ссылочное поле
  (это не идентичность самого элемента).
- **Top-level ключи массивов** (`available`/`ready`/`tasks`) этой задачей
  **не** меняются — унифицируется форма *элемента*, а не имя контейнера;
  переименование контейнеров — отдельный вопрос вне охвата.
- **Команды вне охвата.** `owl next`, `owl task ready-steps`,
  `owl task aggregate-status` уже используют `task_id` как *ссылку* на
  задачу (верхний уровень / dispatch), а не как задачу-объект — их не трогаем.
- **Схемы JSON.** Если существует `schemas/task.json` или иной published
  schema, описывающий эти выводы, его нужно синхронизировать с новым
  контрактом (тоже часть ломающего изменения).

# Acceptance criteria

- [ ] `owl task available --json`, `owl task ready --json`,
  `owl task list --json` отдают идентификатор задачи под ключом `task_id`;
  ключа `id` как идентификатора нет ни в одном элементе.
- [ ] Все три команды содержат общее ядро полей `task_id`, `title`, `kind`,
  `priority`, `created_at`, `status`, `workflow` с одинаковыми именами и
  семантикой.
- [ ] Специфичные поля сохранены: `available` → `ready_step_ids`, `reason`;
  `ready`/`list` → `labels`, `blocked_by`, `archived_at`, `parent_id`.
- [ ] `--dep-aware`-ветка `available` отдаёт тот же контракт.
- [ ] Все внутренние потребители (`owl-*` скиллы, orchestrator, код в
  `lib/owl`) обновлены и читают `task_id`; релевантные specs зелёные.
- [ ] Если есть published JSON-schema для этих выводов — синхронизирована.
- [ ] `Owl::VERSION` повышен по major; добавлена запись в `CHANGELOG.md` в
  том же коммите.
- [ ] 100% line coverage для затронутых `lib/owl/**/api.rb` сохранено.
