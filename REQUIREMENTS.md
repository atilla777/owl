# Owl — Требования к системе

Этот документ описывает функциональные требования к Owl, примеры конфигураций/схем/артефактов и интерфейс CLI. Концептуальное описание — в [AGENTS.md](AGENTS.md), архитектура — в [ARCHITECTURE.md](ARCHITECTURE.md), план реализации — в [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

---

## 1. Общие требования

Owl должен:

```text
1. Поддерживать разные типы workflow.
2. Хранить каждый workflow в отдельной схеме.
3. Иметь реестр зарегистрированных workflow.
4. Поддерживать переиспользуемые типы артефактов.
5. Хранить шаблоны артефактов отдельно от workflow.
6. Поддерживать настройку путей хранения.
7. Работать без СУБД в первой версии, но быть готовым к переходу на неё.
8. Использовать файловое состояние как default backend.
9. Предоставлять CLI как единый machine API для агентов и skills.
10. Позволять в будущем заменить файловое состояние на SQLite/БД/remote backend.
11. Поддерживать декомпозицию: parent/composite task с child tasks, плоское хранение, parent_id-связь.
```

---

## 2. Требования к хранению

По умолчанию:

```text
.owl/
  конфигурация Owl, workflow, artifacts, schemas

tasks/
  index, текущие задачи (плоско, parent и child вперемешку), рабочие артефакты, архив задач

docs/
  опубликованные доменные знания проекта
```

Физические пути не должны быть зашиты в workflow. Workflow должен использовать логические storage roles. Текущая реализация определяет шесть стандартных ролей в `lib/owl/storage/api.rb` (`STANDARD_ROLES`):

```text
control       # .owl/ — workflows, artifact-types, overlays, конфиг
local_state   # .owl/local/ — current.yaml и другая per-session машинная память
index         # tasks/index.yaml — производный индекс задач
tasks         # tasks/ — рабочие артефакты задач
archive       # tasks/archive/ — завершённые задачи
docs          # docs/ — опубликованные доменные знания
```

Пример (актуальный seeded `workflows/feature/workflow.yaml`):

```yaml
storage:
  role: tasks
  path: "{{task.id}}/brief.md"
```

а не:

```yaml
path: "tasks/TASK-0001/brief.md"
```

> **Historical:** ранние черновики использовали логический набор `state | artifact | archive | docs`.
> Реализация развела его до шести ролей выше, чтобы явно разделить read/write surface
> (`tasks` vs `docs`), производный индекс (`index`), per-session машинную память
> (`local_state`) и конфиг (`control`).

---

## 3. Требования к CLI

CLI должен быть главным API для работы с состоянием.

Skills должны вызывать:

```bash
owl task index rebuild --json
owl task tree --json
owl task children TASK-0001 --json
owl task parent TASK-0002 --json
owl task child create TASK-0001 \
  --title "Add backend endpoint" \
  --workflow feature_slice \
  --json

owl task aggregate-status TASK-0001 --json
owl task ready --json   # читает tasks/index.yaml, при необходимости пересобирая
```

Skills не должны напрямую читать и писать `tasks/index.yaml`, если это можно сделать через CLI.

На первой версии допустимо, что CLI внутри работает с YAML/Markdown-файлами. Но внешний контракт CLI должен быть стабильным.

---

## 4. Требования к workflow

Workflow должен быть YAML-файлом.

Он должен описывать:

```text
- id;
- kind (task | composite_task);
- version;
- title;
- selection aliases;
- artifacts;
- steps;
- dependencies;
- conditions;
- publish behavior;
- archive behavior;
- skill delegation;
- validation requirements;
- (для composite) правила декомпозиции и агрегации статуса.
```

Workflow должен быть валидируемым через JSON Schema.

### 4.1. Композитные и слайс-workflow

Для задач, требующих декомпозиции, существует отдельный класс workflow (`composite_*`):

```text
composite_feature:
  brief → specify → design? → decompose → coordinate → aggregate_verify → publish → archive
```

Для дочерних задач — облегчённый workflow:

```text
feature_slice:
  plan → apply → verify
```

Композитная задача не обязана сама писать код — она может:

```text
- описать общую цель (brief);
- создать specs/design;
- разбить работу на child tasks (decompose);
- координировать выполнение (coordinate);
- собрать итоговую верификацию (aggregate_verify);
- опубликовать итоговые docs;
- архивировать всё дерево.
```

Шаг `decompose` объявляет `may_create_tasks: true` — это разрешение CLI/skill создавать child tasks.

---

## 5. Требования к артефактам

Артефакты должны быть переиспользуемыми.

Каждый artifact type должен иметь:

```text
- id;
- title;
- kind;
- template;
- validation;
- agent_hints;
- optional front matter rules.
```

Большинство артефактов — Markdown-файлы.

Markdown-артефакты могут иметь YAML front matter:

```md
---
artifact: spec
task_id: TASK-0001
workflow: feature
status: draft
---

## Requirements
...
```

Но source of truth для состояния — не front matter, а state/index, доступные через CLI.

### 5.1. Иерархия артефактов задачи

Важно различать три уровня описания работы:

```text
1. Parent task / composite task   — большая задача-контейнер с собственным task.yaml.
2. Child task / subtask           — отдельная управляемая задача со своим workflow,
                                    состоянием и артефактами; ссылается на parent через parent_id.
3. tasks.md checklist             — низкоуровневые implementation steps внутри одной задачи.
```

`tasks.md` — это checklist реализации **внутри** конкретной задачи; `subtask` — это полноценная задача с собственным `task.yaml`. Эти понятия не должны смешиваться.

---

## 6. Требования к index и задачам

### 6.1. Index

`tasks/index.yaml` — производный от реальных `task.yaml` индекс актуальных (не завершённых) задач. CLI должен уметь его пересобирать (`owl task index rebuild`).

Каждая запись индекса должна позволять:

```text
- определить готовые задачи (ready);
- определить задачи в работе (in_progress);
- предложить кандидатов для current_task.
```

### 6.2. Task

Каждая задача должна иметь:

```text
- id;
- kind: task | composite_task;
- title;
- workflow;
- status;
- priority;
- current_step;
- dependencies;
- blocked_by;
- branch;
- domains;
- parent_id          (только у child task);
- children.order     (только у composite task);
- completion.strategy (только у composite task: all_children_done | any_child_done | manual).
```

Каждая задача должна иметь отдельную папку:

```text
tasks/TASK-0001/
```

Внутри неё артефакты, например:

```text
task.yaml
brief.md
specs/
design.md
decomposition.md
tasks.md
verification.md
```

### 6.3. Текущая задача

Не должна быть одной глобальной переменной для всего проекта. Теоретически одновременно может быть несколько активных задач.

Текущая задача должна определяться по приоритету:

```text
1. явно переданный task id;
2. самая приоритетная;
3. самая старая.
```

Хранится в `.owl/local/current.yaml` (не коммитится).

### 6.4. Декомпозиция и подзадачи

Подзадачи хранятся **плоско** в `tasks/`, связь — через поле `parent_id` в child task.

Причины плоского хранения:

```text
- проще искать задачи;
- проще архивировать;
- проще строить дерево;
- проще ссылаться между задачами;
- подзадачу можно потом сделать самостоятельной;
- не надо переносить папки при изменении иерархии.
```

Composite task в своём `task.yaml` хранит только `children.order` (порядок) и стратегию завершения; полное состояние детей берётся из их собственных `task.yaml`. CLI команда `owl task tree --json` собирает дерево по `parent_id`.

Агрегация статуса composite task (`owl task aggregate-status`) считается по children согласно `completion.strategy`.

---

## 7. Требования к docs

`docs` хранит доменные знания проекта (вероятно, это тоже артефакты).

Пример:

```text
docs/
  user-export/
    spec.md
    glossary.md
    decisions.md

  billing/
    spec.md
    invariants.md

  auth/
    spec.md
```

Workflow типа `feature`/`composite_feature` должен создавать proposed domain specs в папке задачи, а затем на шаге `publish` обновлять `docs`.

---

## 8. Требования к персональному режиму

Первая версия Owl — персональный инструмент без СУБД.

Это означает:

```text
- не требуется сложная multi-user синхронизация;
- файловые конфликты можно решать вручную;
- locks нужны скорее как подсказка, чем как строгий distributed locking;
- index и tasks могут храниться в git или не храниться — на выбор пользователя;
- CLI должен быть готов к будущему backend abstraction.
```

---

## 9. Примеры конфигураций, схем и артефактов

### 9.1. `.owl/config.yaml`

```yaml
schema_version: 1

project:
  id: my-rails-app
  title: My Rails App
  root: "{{cwd}}"

owl:
  control_root: "{{project.root}}/.owl"

workflow:
  default: feature

storage:
  active_profile: default

  profiles:
    default:
      backend: filesystem

      roles:
        control:
          path: "{{project.root}}/.owl"

        local_state:
          path: "{{project.root}}/.owl/local"

        index:
          path: "{{project.root}}/tasks/index.yaml"

        tasks:
          path: "{{project.root}}/tasks"

        archive:
          path: "{{project.root}}/tasks/archive"

        docs:
          path: "{{project.root}}/docs"

    obsidian:
      backend: filesystem

      roles:
        control:
          path: "{{project.root}}/.owl"

        local_state:
          path: "{{project.root}}/.owl/local"

        index:
          path: "{{env.OBSIDIAN_VAULT}}/Projects/{{project.id}}/tasks/index.yaml"

        tasks:
          path: "{{env.OBSIDIAN_VAULT}}/Projects/{{project.id}}/tasks"

        archive:
          path: "{{env.OBSIDIAN_VAULT}}/Projects/{{project.id}}/tasks/archive"

        docs:
          path: "{{env.OBSIDIAN_VAULT}}/Projects/{{project.id}}/docs"
```

---

### 9.2. `.owl/workflows.yaml`

```yaml
schema_version: 1

default_workflow: feature

resolution:
  order:
    - explicit_argument
    - task_metadata
    - project_default
    - registry_default

workflows:
  feature:
    enabled: true
    version: "1.0"
    source: "workflows/feature/workflow.yaml"
    title: "Feature development"
    aliases:
      - feature
      - story
      - behavior-change
    priority: 50

  composite_feature:
    enabled: true
    version: "1.0"
    source: "workflows/composite_feature/workflow.yaml"
    title: "Composite feature (with decomposition)"
    aliases:
      - composite_feature
      - epic
      - multi-slice-feature
    priority: 55

  feature_slice:
    enabled: true
    version: "1.0"
    source: "workflows/feature_slice/workflow.yaml"
    title: "Feature slice (child task)"
    aliases:
      - feature_slice
      - slice
      - subtask
    priority: 45

```

---

### 9.3. `.owl/artifacts.yaml`

```yaml
schema_version: 1

artifacts:
  brief:
    source: "artifacts/brief/artifact.yaml"

  design:
    source: "artifacts/design/artifact.yaml"

  plan:
    source: "artifacts/plan/artifact.yaml"

  review:
    source: "artifacts/review/artifact.yaml"

  decomposition:
    source: "artifacts/decomposition/artifact.yaml"

  verification:
    source: "artifacts/verification/artifact.yaml"
```

---

### 9.4. Artifact type: `.owl/artifacts/decomposition/artifact.yaml`

```yaml
schema_version: 1

id: decomposition
title: Task decomposition
kind: markdown

default_template: "templates/default.md"

validation:
  required_sections:
    - "Strategy"
    - "Child Tasks"

agent_hints:
  purpose: >
    Describe how to split a composite task into independent child tasks
    that can be executed by their own workflows.

  must:
    - "Define a clear decomposition strategy (vertical/technical slices, layers, etc.)."
    - "List each proposed child task with scope and dependencies."
    - "Each child task should be independently testable and verifiable."

  avoid:
    - "Do not describe low-level implementation details — those belong in child tasks.md."
```

Пример `decomposition.md`:

```md
---
artifact: decomposition
task_id: TASK-0001
status: accepted
---

# Decomposition

## Strategy

Split the feature into vertical slices.

## Child Tasks

### TASK-0002 Backend endpoint
Scope:
- Add export endpoint
- Add authorization
- Return CSV response
Depends on:
- none

### TASK-0003 UI entry point
Scope:
- Add export button
- Add loading state
Depends on:
- TASK-0002

### TASK-0004 Tests and verification
Scope:
- Add request specs
- Add system specs
- Verify CSV content
Depends on:
- TASK-0002
- TASK-0003
```

---

### 9.5. Feature workflow: `.owl/workflows/feature/workflow.yaml`

Используется для одиночных, не требующих декомпозиции задач.

> **Historical — per-step `skill:` биндинги (`owl.steps.brief`, `owl.steps.specify`, …)
> в примере ниже описывают раннюю модель проекта. Текущая реализация привязывает
> каждый шаг seeded-workflow к универсальному `owl-step-run` (см.
> `skills/owl-step-run/SKILL.md`); per-step skills остаются доступной точкой
> расширения для кастомных workflow, но seeded YAML использует общий исполнитель.
> Актуальный seeded workflow — `workflows/feature/workflow.yaml` в репозитории.**

```yaml
schema_version: 1

id: feature
kind: task
title: Feature workflow
version: "1.0"

selection:
  aliases:
    - feature
    - story
    - behavior-change

  examples:
    - "Add CSV export for users"
    - "Add dark mode"
    - "Change checkout behavior"

artifacts:
  brief:
    type: brief
    title: Feature brief
    storage:
      role: work
      path: "{{task.id}}/brief.md"

  specs:
    type: spec
    title: Proposed domain specs
    multiple: true
    storage:
      role: work
      path: "{{task.id}}/specs/**/*.md"
    publish:
      role: docs
      path: "{{domain}}/spec.md"

  design:
    type: design
    title: Technical design
    optional: true
    storage:
      role: work
      path: "{{task.id}}/design.md"

  tasks:
    type: tasks
    title: Implementation tasks
    storage:
      role: work
      path: "{{task.id}}/tasks.md"

  verification:
    type: verification
    title: Verification report
    storage:
      role: work
      path: "{{task.id}}/verification.md"

steps:
  brief:
    title: Create feature brief
    skill: owl.steps.brief
    creates:
      - brief
    requires: []

  specify:
    title: Create proposed domain specs
    skill: owl.steps.specify
    creates:
      - specs
    requires:
      - brief

  design:
    title: Create technical design
    skill: owl.steps.design
    creates:
      - design
    requires:
      - brief
      - specify
    when: "task.variables.risk != 'low' or task.variables.touches_architecture == true"

  plan:
    title: Create implementation tasks
    skill: owl.steps.plan
    creates:
      - tasks
    requires:
      - specify
    uses_if_present:
      - design

  apply:
    title: Implement tasks
    skill: owl.steps.apply
    creates: []
    requires:
      - plan
    tracks:
      artifact: tasks
      checkbox_pattern: "^- \\[ \\]"

  verify:
    title: Verify implementation
    skill: owl.steps.verify
    creates:
      - verification
    requires:
      - apply

  publish:
    title: Publish accepted domain specs
    skill: owl.steps.publish
    creates: []
    requires:
      - verify
    publishes:
      - specs

  archive:
    title: Archive completed task
    skill: owl.steps.archive
    creates: []
    requires:
      - publish
    moves:
      from:
        role: work
        path: "{{task.id}}"
      to:
        role: archive
        path: "{{date}}-{{task.id}}-{{task.slug}}"
```

---

### 9.6. Composite feature workflow: `.owl/workflows/composite_feature/workflow.yaml`

Используется для крупных задач, которые разбиваются на child tasks.

```yaml
schema_version: 1

id: composite_feature
kind: composite_task
title: Composite feature workflow
version: "1.0"

selection:
  aliases:
    - composite_feature
    - epic
    - multi-slice-feature

  examples:
    - "Add user CSV export (backend + UI + tests)"
    - "Migrate billing module to new provider"

artifacts:
  brief:
    type: brief
    storage:
      role: work
      path: "{{task.id}}/brief.md"

  specs:
    type: spec
    multiple: true
    storage:
      role: work
      path: "{{task.id}}/specs/**/*.md"
    publish:
      role: docs
      path: "{{domain}}/spec.md"

  design:
    type: design
    optional: true
    storage:
      role: work
      path: "{{task.id}}/design.md"

  decomposition:
    type: decomposition
    storage:
      role: work
      path: "{{task.id}}/decomposition.md"

steps:
  brief:
    title: Create feature brief
    skill: owl.steps.brief
    creates:
      - brief
    requires: []

  specify:
    title: Create proposed domain specs
    skill: owl.steps.specify
    creates:
      - specs
    requires:
      - brief

  design:
    title: Create technical design
    skill: owl.steps.design
    creates:
      - design
    requires:
      - specify
    when: "task.variables.risk != 'low' or task.variables.touches_architecture == true"

  decompose:
    title: Decompose into child tasks
    skill: owl.steps.decompose
    creates:
      - decomposition
    requires:
      - brief
      - specify
    uses_if_present:
      - design
    may_create_tasks: true

  coordinate:
    title: Coordinate child tasks execution
    skill: owl.steps.coordinate
    creates: []
    requires:
      - decompose
    tracks:
      children: true

  aggregate_verify:
    title: Aggregate verification from children
    skill: owl.steps.aggregate_verify
    creates: []
    requires:
      - coordinate
    completion:
      strategy: all_children_done

  publish:
    title: Publish accepted domain specs
    skill: owl.steps.publish
    creates: []
    requires:
      - aggregate_verify
    publishes:
      - specs

  archive:
    title: Archive completed task tree
    skill: owl.steps.archive
    creates: []
    requires:
      - publish
    moves:
      from:
        role: work
        path: "{{task.id}}"
      to:
        role: archive
        path: "{{date}}-{{task.id}}-{{task.slug}}"
    archives_children: true
```

---

### 9.7. Feature slice workflow: `.owl/workflows/feature_slice/workflow.yaml`

Облегчённый workflow для child tasks.

```yaml
schema_version: 1

id: feature_slice
kind: task
title: Feature slice (child task) workflow
version: "1.0"

selection:
  aliases:
    - feature_slice
    - slice
    - subtask

artifacts:
  tasks:
    type: tasks
    storage:
      role: work
      path: "{{task.id}}/tasks.md"

  verification:
    type: verification
    storage:
      role: work
      path: "{{task.id}}/verification.md"

steps:
  plan:
    title: Create implementation tasks
    skill: owl.steps.plan
    creates:
      - tasks
    requires: []

  apply:
    title: Implement tasks
    skill: owl.steps.apply
    creates: []
    requires:
      - plan
    tracks:
      artifact: tasks
      checkbox_pattern: "^- \\[ \\]"

  verify:
    title: Verify implementation
    skill: owl.steps.verify
    creates:
      - verification
    requires:
      - apply
```

---

### 9.8. Index: `tasks/index.yaml`

`index.yaml` — производный (от реального состояния задач в папке `tasks/`) индекс ещё не завершённых задач.

```yaml
schema_version: 1
kind: task_index
source_of_truth: "tasks/*/task.yaml"
generated_at: "2026-05-17T16:00:00+02:00"

ready:
  - id: TASK-0002
    path: TASK-0002/task.yaml
    parent_id: TASK-0001
  - id: TASK-0005
    path: TASK-0005/task.yaml

in_progress:
  - id: TASK-0001
    path: TASK-0001/task.yaml
    kind: composite_task

blocked:
  - id: TASK-0003
    path: TASK-0003/task.yaml
    parent_id: TASK-0001
    blocked_by:
      - TASK-0002

current_candidates:
  - id: TASK-0002
    path: TASK-0002/task.yaml
```

---

### 9.9. Composite task state: `tasks/TASK-0001/task.yaml`

```yaml
schema_version: 1

id: TASK-0001
kind: composite_task
title: Add user CSV export
workflow: composite_feature
status: active
priority: P2

created_at: "2026-05-17T12:00:00+02:00"
updated_at: "2026-05-17T15:00:00+02:00"

branch: feature/user-csv-export

domains:
  - user-export

variables:
  risk: medium
  domain: user-export
  touches_architecture: false

children:
  order:
    - TASK-0002
    - TASK-0003
    - TASK-0004

completion:
  strategy: all_children_done   # all_children_done | any_child_done | manual

steps:
  brief:
    status: done
    completed_at: "2026-05-17T12:20:00+02:00"
  specify:
    status: done
  design:
    status: done
  decompose:
    status: done
  coordinate:
    status: ready
  aggregate_verify:
    status: blocked
    blocked_by:
      - children
  publish:
    status: blocked
    blocked_by:
      - aggregate_verify
  archive:
    status: blocked
    blocked_by:
      - publish

artifacts:
  brief:
    status: accepted
    path: brief.md
  specs:
    status: accepted
    path: specs/**/*.md
  design:
    status: accepted
    path: design.md
  decomposition:
    status: accepted
    path: decomposition.md

locks:
  docs:
    - user-export
  files: []
```

---

### 9.10. Child task state: `tasks/TASK-0002/task.yaml`

```yaml
schema_version: 1

id: TASK-0002
kind: task
title: Add backend endpoint for user CSV export
workflow: feature_slice
status: ready
priority: P2

parent_id: TASK-0001

created_at: "2026-05-17T13:00:00+02:00"
updated_at: "2026-05-17T13:00:00+02:00"

branch: feature/user-csv-export-backend

domains:
  - user-export

dependencies: []
blocked_by: []

variables:
  domain: user-export
  slice: backend

steps:
  plan:
    status: ready
  apply:
    status: pending
  verify:
    status: pending

artifacts:
  tasks:
    status: missing
    path: tasks.md
  verification:
    status: missing
    path: verification.md
```

---

### 9.11. Standalone task state: `tasks/TASK-0010/task.yaml`

Пример обычной (не дочерней) задачи без декомпозиции — `kind: task`, без `parent_id`.

```yaml
schema_version: 1

id: TASK-0010
kind: task
title: Fix login redirect bug
workflow: feature
status: active
priority: P0

created_at: "2026-05-17T09:00:00+02:00"
updated_at: "2026-05-17T09:30:00+02:00"

branch: feature/login-redirect

domains:
  - auth

dependencies: []
blocked_by:
  - type: external
    reason: "Waiting for production logs"

steps:
  brief:
    status: done
  plan:
    status: ready
  implement:
    status: pending
  review_code:
    status: pending
  merge_docs:
    status: pending
  archive:
    status: pending
  commit_push:
    status: pending

artifacts:
  brief:
    status: accepted
    path: brief.md
  plan:
    status: missing
    path: plan.md
```

---

### 9.12. Local current task: `.owl/local/current.yaml`

```yaml
schema_version: 1

current_task_id: TASK-0002
session_id: default
agent_id: local-agent
last_used_at: "2026-05-17T15:35:00+02:00"
```

Этот файл не коммитится.

---

## 10. CLI: предлагаемый интерфейс

### 10.1. Инициализация

```bash
owl init
owl init --profile rails
owl init --force
```

Создаёт:

```text
.owl/
tasks/
docs/
```

### 10.2. Workflow

```bash
owl workflow list --json
owl workflow show feature --json
owl workflow show composite_feature --json
owl workflow validate feature --json
owl workflow new --id <id> [--kind task|composite_task] [--from <existing>] [--body -] [--force]
```

> `owl workflow validate --all` пока не реализован — валидация выполняется по
> отдельному id или path. См. `bin/owl workflow --help` для актуального набора.

### 10.3. Artifact types

```bash
owl artifact-type list --json
owl artifact-type show spec --json
owl artifact-type validate spec --json
owl artifact-type new --id <id> [--body -] [--force]
```

### 10.4. Tasks / work items

```bash
owl task create \
  --workflow feature \
  --title "Add user CSV export" \
  --domain user-export \
  --json

owl task list --json
owl task list --status active --json

owl task current --json
owl task use TASK-0001 --json

owl task inspect TASK-0001 --json
owl task ready-steps TASK-0001 --json
# Future / not yet implemented: owl task blockers, owl task conflicts.
# Используй `owl status TASK-0001 --json` — он возвращает шаги с ready flag,
# progress {done, total, pct} и blockers.

# Index management
owl task index rebuild --json
# Future / not yet implemented: owl task ready (snapshot из tasks/index.yaml).

# Subtasks / tree
owl task tree --json
owl task children TASK-0001 --json
owl task parent TASK-0002 --json
owl task aggregate-status TASK-0001 --json

# Декомпозиция: создание подзадач
owl task child create TASK-0001 \
  --title "Add backend endpoint" \
  --workflow feature_slice \
  --json
```

### 10.5. Steps

```bash
owl step invocation TASK-0001 specify --json
owl step show TASK-0001 specify --json   # merged bundle: step + context + artifact_template + task
owl step start TASK-0001 specify --json
owl step complete TASK-0001 specify --json
owl step skip TASK-0001 design --reason "Low risk" --json
```

### 10.6. Artifacts of task

```bash
owl artifact resolve TASK-0001 brief --json
owl artifact resolve TASK-0001 specs --json
owl artifact validate TASK-0001 specs --json
```

> `owl artifact read` / `owl artifact write` пока не реализованы — артефакт читается
> через `owl step show ... --json` (поле `task.artifacts`) и пишется напрямую в путь,
> возвращённый `owl artifact resolve`, согласно `skills/owl-step-run/SKILL.md`.

### 10.7. Publish / archive

```bash
owl publish TASK-0001 --json
owl archive TASK-0001 --json
```

### 10.8. Validation

```bash
owl config validate --json
```

> Future / not yet implemented: `owl state validate`, `owl index validate`.
> Текущая валидация state выполняется через `owl status TASK-ID --json` (агрегация шагов
> и блокеров) и `owl task index rebuild --json` (перестроение индекса при дрейфе).
