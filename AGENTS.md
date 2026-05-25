# Owl — система управления AI-разработкой через workflow, артефакты и состояние задач

Формула проекта в одном абзаце — это workflow-система для AI-assisted разработки, где `.owl` хранит конфигурацию, workflow-схемы и шаблоны артефактов, `tasks` хранит index и рабочие задачи с артефактами, а `docs` хранит опубликованные доменные знания проекта. Оркестратор через Owl CLI определяет текущую задачу и следующий доступный шаг, вызывает специализированный skill, skill создаёт артефакт по шаблону, CLI валидирует результат и обновляет состояние. Workflow описываются декларативно в YAML, артефакты переиспользуются между workflow, а физические пути задаются через storage roles, чтобы в будущем можно было заменить файловое хранилище на Obsidian, SQLite или другой backend без переписывания skills.

## Документация

- [ARCHITECTURE.md](ARCHITECTURE.md) — высокоуровневая архитектура, компоненты, структура папок, пример StepInvocation, дерево задач.
- [REQUIREMENTS.md](REQUIREMENTS.md) — функциональные требования, примеры конфигураций/схем/артефактов, интерфейс CLI.
- [IMPLEMENTATION_PLAN.md (архивный снапшот)](docs/historical/2026-05-implementation-plan.md) — поэтапный план реализации до MVP и далее (исторический snapshot; актуальный roadmap живёт в KOS).

---

## 1. Цель и концепция проекта

**Owl** — персональный инструмент для управления AI-assisted разработкой по принципу SDD/spec-driven development, но с гибкой системой workflow.

Главная идея: разные типы задач разработки имеют разные последовательности шагов, разные артефакты и разные правила выполнения. Например:

```text
feature:
  brief → spec → design? → tasks → apply → verify → publish → archive

composite_feature (большая задача с декомпозицией):
  brief → spec → design? → decompose → coordinate → aggregate_verify → publish → archive

feature_slice (дочерняя задача):
  plan → apply → verify
```

Сценарии «исправить баг» и «отрефакторить кусок» не имеют собственного
workflow — это варианты шага `brief` внутри `feature` /
`composite_feature` (см. раздел «Step variants» в README). Дальше задача
идёт по тому же стандартному графу: `brief → design → plan → implement →
review_code → ...`.

Owl должен позволять описывать такие workflow декларативно — через YAML-схемы. Оркестратор читает схему workflow, понимает текущую задачу, определяет следующий доступный шаг, вызывает соответствующий skill/агента, а агент создаёт или обновляет нужный артефакт.

Проект вдохновлён подходом OpenSpec/OPSX, но Owl должен быть более явно ориентирован на:

```text
- переиспользуемые типы артефактов;
- отдельный реестр workflow;
- настраиваемые пути хранения;
- работу через CLI как стабильный machine API;
- персональное использование без обязательной СУБД;
- возможность будущей замены файлового состояния на БД или другой backend;
- декомпозицию сложных задач на подзадачи (composite_task / child task).
```

Ключевая концепция:

```text
Workflow описывает не просто список шагов, а граф шагов и артефактов.
Артефакт — центральная единица результата.
Состояние задачи хранится отдельно от workflow-схемы.
Сложные задачи могут декомпозироваться на child tasks (плоское хранение, связь через parent_id).
Skills не должны сами угадывать пути, текущую задачу и статус workflow.
Они должны получать это через Owl CLI.
```

---

## 2. Основные понятия и термины

### Owl

Сам проект/инструмент. Управляет workflow, задачами, артефактами, состоянием и публикацией доменных знаний.

### `.owl`

Служебная папка конфигурации Owl.

В ней хранятся:

```text
- конфиг проекта;
- реестр workflow;
- схемы workflow;
- реестр типов артефактов;
- шаблоны артефактов;
- JSON Schema для валидации;
- локальное runtime-состояние агента, если нужно.
```

`.owl` — это control plane.

### `tasks`

Папка в корне проекта для текущих задач, index и рабочих артефактов.

Важно: папка называется именно `tasks`, а не `owl/tasks`, потому что потенциально она может использоваться не только Owl, но и другими инструментами.

`tasks` — это рабочая зона задач.

### `docs`

Папка в корне проекта для доменных знаний проекта.

Туда публикуются итоговые спецификации/описания доменных областей после завершения workflow. Это аналог "актуального source of truth" для поведения и доменной логики проекта.

Важно: не использовать `spec` или `specs` в корне Rails-проекта, чтобы избежать конфликта и путаницы с RSpec.

### Workflow

Описание типа задачи.

Сейчас seed-набор:

```text
feature
composite_feature
```

Произвольные пользовательские workflow создаются командой `owl workflow new`.

Каждый workflow имеет отдельную YAML-схему:

```text
.owl/workflows/feature/workflow.yaml
.owl/workflows/composite_feature/workflow.yaml
```

Workflow описывает:

```text
- какие артефакты нужны;
- какие шаги есть;
- какой skill вызывается на каждом шаге;
- какие зависимости между шагами;
- какие артефакты создаёт шаг;
- какие условия применяются;
- разрешает ли шаг создавать child tasks (may_create_tasks);
- как публиковать результаты в docs;
- как архивировать завершённую задачу.
```

### Workflow registry

Реестр зарегистрированных workflow.

Файл:

```text
.owl/workflows.yaml
```

Нужен, чтобы Owl знал:

```text
- какие workflow доступны;
- какой workflow используется по умолчанию;
- какие aliases есть у workflow;
- где лежит схема workflow;
- включён ли workflow в проекте.
```

### Artifact

Артефакт — результат одного или нескольких шагов workflow.

Примеры (seed-набор):

```text
brief.md
design.md
plan.md
review.md
decomposition.md
verification.md
```

Артефакт обычно является Markdown-файлом, но его тип и правила описываются отдельно.

### Artifact type

Переиспользуемый тип артефакта.

Например, `brief` используется в `feature` и `composite_feature` — это переиспользование одного описания артефакта между разными workflow.

Тип артефакта описывает:

```text
- назначение;
- шаблон;
- обязательные секции;
- правила валидации;
- подсказки для агента;
- ограничения.
```

Хранится, например:

```text
.owl/artifacts/brief/artifact.yaml
.owl/artifacts/brief/templates/default.md
```

### Work item (task)

Единица работы верхнего уровня.

Например:

```text
TASK-0001 Add user CSV export
TASK-0002 Fix login redirect bug
TASK-0003 Refactor billing module
```

Задача имеет поле `kind`, которое определяет её роль в дереве:

```text
kind: task             — обычная задача (в т.ч. дочерняя — со ссылкой parent_id);
kind: composite_task   — задача-контейнер, декомпозируемая на child tasks.
```

Важно не путать:

```text
tasks/
  папка текущих задач (плоско: parent и child вперемешку)

tasks.md
  артефакт внутри конкретной задачи, checklist реализации
```

### Parent / composite task

Большая задача-контейнер с `kind: composite_task`. Не пишет код сама — она:

```text
- описывает общую цель (brief);
- создаёт specs/design;
- разбивает работу на child tasks (decompose);
- координирует выполнение (coordinate);
- собирает итоговую верификацию (aggregate_verify);
- публикует итоговые docs;
- архивирует всё дерево.
```

В `task.yaml` parent хранит:

```text
- children.order        — порядок child tasks;
- completion.strategy   — all_children_done | any_child_done | manual.
```

Полное состояние каждого child берётся из его собственного `task.yaml`.

### Child task / subtask

Полноценная задача со своим `task.yaml`, workflow, состоянием и артефактами. От parent её отличает поле `parent_id`. Хранится **плоско** в `tasks/` (а не вложенно в папку parent) — так проще искать, архивировать, перепривязывать и при необходимости делать самостоятельной.

Подзадачу не следует путать с `tasks.md`:

```text
tasks.md       — checklist реализации внутри одной задачи (низкоуровневый);
child task     — отдельная управляемая задача со своим workflow.
```

### Three levels of work

Чтобы не путать масштабы декомпозиции:

```text
1. Parent / composite task        — большая задача-контейнер.
2. Child task / subtask           — отдельная управляемая задача (со своим task.yaml).
3. tasks.md checklist             — низкоуровневые implementation steps внутри одной задачи.
```

### Index (Roadmap)

Общий список актуальных (не завершённых) задач проекта.

По умолчанию хранится:

```text
tasks/index.yaml
```

Index — производный (от реальных `task.yaml` в папке `tasks`) индекс ещё не завершённых задач. Содержит группы `ready`, `in_progress`, `blocked`, `current_candidates` и т.п. Может пересобираться командой `owl task index rebuild`. Дерево parent/child вытаскивается по `parent_id` через `owl task tree --json`.

### Current task

Текущая задача для конкретной сессии/агента.

Не должна быть одной глобальной переменной для всего проекта. Теоретически одновременно может быть несколько активных задач.

Текущая задача должна определяться по приоритету:

```text
1. явно переданный task id;
2. самая приоритетная;
3. самая старая.
```

### Step

Шаг workflow.

Например:

```text
brief
specify
design
decompose
coordinate
plan
apply
verify
aggregate_verify
publish
archive
```

Step описывает:

```text
- id;
- title;
- skill;
- required previous steps;
- created artifacts;
- optional artifacts;
- conditions;
- validation;
- failure policy;
- may_create_tasks (флаг разрешения порождать child tasks).
```

### Frontmatter for `.context.md`

Шаги ссылаются на текстовый контекст через `context_file:` (или `variants.<name>.context_file:`). Файл `.context.md` может опционально начинаться с YAML-frontmatter, который явно описывает, к какому шагу относится контекст:

```yaml
---
step_id: design
applies_to_session_type: discussion
intended_audience: orchestrator
applies_to_variants: [feature]   # только для variant-шагов
summary: "Краткое описание шага."
---
```

Поля (все опциональные):

```text
- step_id                   — id шага из workflow.yaml; ошибка, если не совпадает с id шага, к которому файл подключён.
- applies_to_session_type   — discussion | execution; должен совпадать с session_type шага.
- applies_to_variants       — массив variant-ключей; на не-variant-шаге даёт ошибку variants_not_applicable.
- intended_audience         — orchestrator | subagent.
- summary                   — однострочное описание; рантайм не использует, только для людей.
```

Naming-convention для context-файлов: `<step_id>[.<variant>].context.md` (3 или 4 dot-сегмента в basename). Файлы с большим числом сегментов (`brief.feature.v2.context.md`) или dotted step_id не выводятся автоматически; для них требуется явный `step_id` во frontmatter.

Валидация запускается из `owl workflow validate` после KOS-155 (`FilesystemRefsCheck`). По умолчанию missing-frontmatter и противоречия дают **warnings**; чтобы повысить до error для отдельного шага — задайте `drift_policy: block` (см. [Решение 8 — drift_policy](#решение-8)). Для понижения до полного игнора — `drift_policy: ignore`.

Схема контракта — `schemas/step_context_frontmatter.json`. Локальный override через `.owl/schemas/step_context_frontmatter.json` (см. KOS-154) применяется без перезапуска: его можно ужесточить (например, убрать значение из enum) — существующие репо-файлы тогда начнут падать на schema-violation, что by design.

Ошибки frontmatter-контракта дают exit code `4` и `error_class: "step_context_frontmatter"` в JSON-payload `owl workflow validate`, отличный от обычной `validation` (exit 1). Возможные `code:` в `error.details.errors` — `step_context_frontmatter_step_id_mismatch`, `step_context_frontmatter_session_type_mismatch`, `step_context_frontmatter_variants_not_applicable`, `step_context_frontmatter_unknown_variant`, `step_context_frontmatter_additional_property`, `step_context_frontmatter_schema_violation`, `step_context_frontmatter_missing` (warning), `step_context_frontmatter_parse_error`, `step_context_frontmatter_invalid_root`, `step_context_frontmatter_unterminated`.

Future work (вне scope KOS-156): `step_context` как полноценный artifact-type со своим шаблоном и required-секциями (Variant 2), и CLI `owl artifact resolve <TASK> step_context --step-id X` для авторинга через CLI (Variant 3).

### Skill

Исполнитель конкретного шага.

> **Historical — superseded by the session-typed step model (RFC #1).**
> Ранние черновики предполагали отдельный skill на каждый шаг
> (`owl.steps.brief`, `owl.steps.design`, …); следующая итерация ввела
> один универсальный `owl-step-run`. Текущая реализация (RFC #1,
> knowledge entry 46) разделяет step-run на два overlay-скилла по
> `session_type`: `owl-step-discussion` (main session, может задавать
> вопросы пользователю) и `owl-step-execution` (subagent, без прямого
> взаимодействия с пользователем; пишет structured report через
> `owl step report --body -`). Оба читают per-step `context` через
> `owl step show`. Per-step skills остаются возможной точкой расширения
> для кастомных workflow.

Skill не должен сам решать, какая задача текущая и куда писать файлы. Он должен получать эту информацию через CLI.

### Orchestrator skill

Главный skill-оркестратор.

Его задача:

```text
- определить текущую задачу;
- прочитать состояние через Owl CLI;
- определить доступные шаги;
- вызвать skill следующего шага;
- после выполнения обновить состояние через Owl CLI.
```

Оркестратор не должен сам писать design/spec/tasks/decomposition. Он делегирует это специализированным skills.

### Decompose

Шаг workflow, на котором composite task разбивается на child tasks.

Skill `owl.steps.decompose`:

```text
- читает brief/specs/design;
- создаёт artifact decomposition.md;
- через CLI (owl task child create) порождает child tasks;
- проставляет parent_id и dependencies между child tasks.
```

Шаг должен иметь `may_create_tasks: true` — это разрешение создавать новые задачи.

### Publish

Шаг, который обновляет `docs`.

Например, во время задачи агент создаёт proposed spec:

```text
tasks/TASK-0001/specs/user-export/spec.md
```

После успешной проверки publish переносит или сливает результат в canonical domain docs:

```text
docs/user-export/spec.md
```

### Archive

Шаг, который завершает задачу и переносит её из активных задач в архив:

```text
tasks/TASK-0001/
```

в:

```text
tasks/archive/2026-05-17-TASK-0001-add-user-export/
```

Для composite task архивация может атомарно перемещать всё дерево (`archives_children: true`).

---

## 3. Важные архитектурные решения

### Решение 1

Используем:

```text
.owl  — для конфигурации;
tasks — для index и текущих задач (плоско, parent/child вперемешку);
docs  — для доменных знаний.
```

### Решение 2

Не используем `spec` или `specs` в корне Rails-проекта.

Причина: конфликт и путаница с RSpec.

### Решение 3

Workflow хранится отдельно для каждого типа задач.

```text
.owl/workflows/feature/workflow.yaml
.owl/workflows/composite_feature/workflow.yaml
```

### Решение 4

Переиспользуемые артефакты описываются отдельно.

```text
.owl/artifacts/brief/artifact.yaml
.owl/artifacts/design/artifact.yaml
.owl/artifacts/decomposition/artifact.yaml
```

### Решение 5

Skills не читают состояние напрямую. Они используют CLI.

### Решение 6

Owl v1 — персональный инструмент без СУБД.

Файлового состояния достаточно для MVP.

### Решение 7

Пути должны быть настраиваемыми через storage roles.

Workflow не должен знать физический путь `tasks/` или `docs/`.

### Решение 8

`docs` — source of truth для доменных знаний.

`tasks/TASK-0001/specs/...` — proposed/spec delta для текущей задачи.

### Решение 9

`tasks/index.yaml` — производный индекс задач (пересобирается из `task.yaml`-файлов).

`.owl/local/current.yaml` — локальный указатель на текущую задачу/сессию (не коммитится).

### Решение 10

Подзадачи хранятся **плоско** в `tasks/`. Связь parent → child — через поле `parent_id` в child `task.yaml`, а не через вложенность папок.

Причины:

```text
- проще искать задачи;
- проще архивировать;
- проще строить дерево;
- проще ссылаться между задачами;
- подзадачу можно потом сделать самостоятельной;
- не надо переносить папки при изменении иерархии.
```

### Решение 11

Различаются три уровня декомпозиции: composite task → child task → tasks.md checklist. `tasks.md` — это implementation checklist внутри одной задачи, а не способ описать подзадачи.
