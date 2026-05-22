# Owl — Архитектура

Этот документ описывает архитектуру системы Owl: высокоуровневую схему, компоненты, структуру папок и пример StepInvocation. Концептуальное описание проекта — в [AGENTS.md](AGENTS.md), требования — в [REQUIREMENTS.md](REQUIREMENTS.md), план реализации — в [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

---

## 1. Высокоуровневая архитектура

```text
User / Agent
   |
   v
Orchestrator Skill
   |
   v
Owl skill
   |
   v
Owl CLI
   |
   +--> Workflow Registry
   +--> Artifact Registry
   +--> Task State
   +--> Index
   +--> Storage Resolver
   +--> Validator
   |
   v
Step Skill
   |
   v
Artifacts / Code / Docs
```

---

## 2. Основные компоненты

### 2.1. Owl CLI

Предпочтительно написать на Ruby (потом перепишем на Go).

Причины:

```text
- быстрый запуск;
- удобно использовать агентам;
- легко отдавать JSON;
- хорошо подходит для работы с файлами;
- можно позже добавить SQLite/backend abstraction.
```

CLI отвечает за:

```text
- чтение конфига;
- разрешение storage roles;
- работу с index;
- создание задач (включая parent/child);
- выбор текущей задачи;
- построение дерева задач (parent_id → children);
- определение ready/blocked steps;
- разрешение путей артефактов;
- валидацию workflow;
- валидацию артефактов;
- обновление состояния шагов;
- агрегацию статуса parent task по children;
- publish (слияние текущей документации и изменений после задачи — это работа для AI агента);
- archive.
```

### 2.2. Orchestrator skill

Использует OWL skill.

Алгоритм:

```text
1. Получить текущую задачу.
2. Если задачи нет — создать.
3. Получить доступные шаги.
4. Выбрать следующий шаг.
5. Получить StepInvocation.
6. Вызвать нужный step skill.
7. После работы skill — проверить артефакт и продвинуть задачу дальше
   (или переместить курсор в index на следующую задачу, если задача выполнена):
   owl artifact validate TASK-0001 specs --json
   owl step complete TASK-0001 specify --json
```

### 2.3. OWL skill

```text
1. Получить текущую задачу:
   owl task current --json

2. Если задачи нет — создать:
   owl task create --workflow feature --title "..." --json

3. Получить доступные шаги:
   owl task ready-steps TASK-0001 --json

4. Выбрать следующий шаг.

5. Получить StepInvocation:
   owl step invocation TASK-0001 specify --json
```

### 2.4. Step skills

Каждый step skill решает узкую задачу.

Примеры:

```text
owl.steps.brief
  создаёт brief.md

owl.steps.specify
  создаёт proposed domain specs

owl.steps.design
  создаёт design.md

owl.steps.decompose
  создаёт decomposition.md и порождает child tasks

owl.steps.plan
  создаёт tasks.md

owl.steps.apply
  реализует задачи из tasks.md

owl.steps.verify
  проверяет соответствие реализации specs/tasks

owl.steps.coordinate
  координирует выполнение child tasks (для composite task)

owl.steps.aggregate_verify
  собирает результаты верификации child tasks

owl.steps.publish
  обновляет docs

owl.steps.archive
  архивирует завершённую задачу
```

### 2.5. Storage resolver

Компонент CLI, который переводит логические роли в физические пути.

Например:

```yaml
role: work
path: "{{task.id}}/brief.md"
```

превращается в:

```text
tasks/TASK-0001/brief.md
```

### 2.6. Validator

Валидирует:

```text
- config.yaml;
- workflows.yaml;
- workflow.yaml;
- artifacts.yaml;
- artifact.yaml;
- index.yaml;
- task.yaml (включая parent/child связи);
- конкретные Markdown-артефакты.
```

Валидация должна быть двух типов:

```text
structural:
  файл существует, секции есть, regex совпадает

semantic:
  requirements покрыты tasks/tests,
  design соответствует specs,
  implementation соответствует verification,
  у child task существует parent с правильным kind,
  у composite task все children разрешимы.
```

В MVP достаточно structural validation.

---

## 3. Структура папок и файлов

### 3.1. Default project layout

Подзадачи хранятся **плоско** в `tasks/` — связь parent → child через поле `parent_id` в `task.yaml`. Это даёт простую навигацию, архивацию и переиспользование child task без физического переноса папок (см. [REQUIREMENTS.md](REQUIREMENTS.md), раздел про подзадачи).

```text
project-root/
  .owl/
    config.yaml
    workflows.yaml
    artifacts.yaml

    workflows/
      feature/
        workflow.yaml
        README.md

      composite_feature/
        workflow.yaml
        README.md

    artifacts/
      brief/
        artifact.yaml
        templates/
          default.md

      design/
        artifact.yaml
        templates/
          default.md

      plan/
        artifact.yaml
        templates/
          default.md

      review/
        artifact.yaml
        templates/
          default.md

      decomposition/
        artifact.yaml
        templates/
          default.md

      verification/
        artifact.yaml
        templates/
          default.md

    schemas/
      owl-config.schema.json
      owl-workflows-registry.schema.json
      owl-workflow.schema.json
      owl-artifacts-registry.schema.json
      owl-artifact.schema.json
      owl-index.schema.json
      owl-task.schema.json

    local/
      current.yaml
      sessions/
        default.yaml

    cache/
    tmp/

  tasks/
    index.yaml

    TASK-0001/                       # parent / composite task
      task.yaml                      # kind: composite_task
      brief.md
      specs/
        user-export/
          spec.md
      design.md
      decomposition.md

    TASK-0002/                       # child of TASK-0001
      task.yaml                      # kind: task, parent_id: TASK-0001
      tasks.md
      verification.md

    TASK-0003/                       # child of TASK-0001
      task.yaml                      # kind: task, parent_id: TASK-0001
      tasks.md
      verification.md

    TASK-0004/                       # standalone bug-fix task (brief variant: root_cause)
      task.yaml                      # kind: task
      brief.md
      plan.md
      verification.md

    archive/
      2026-05-17-TASK-0001-add-user-export/
        task.yaml
        brief.md
        specs/
        design.md
        decomposition.md
      2026-05-17-TASK-0002-add-backend-endpoint/
        task.yaml
        tasks.md
        verification.md

  docs/
    user-export/
      spec.md

    auth/
      spec.md

    billing/
      spec.md
```

### 3.2. Что коммитить в git

Для персонального режима можно оставить гибким.

Рекомендуемый default:

Коммитить:

```text
.owl/config.yaml
.owl/workflows.yaml
.owl/artifacts.yaml
.owl/workflows/**
.owl/artifacts/**
.owl/schemas/**

docs/**
```

Опционально коммитить:

```text
tasks/index.yaml
tasks/TASK-*/**
tasks/archive/**
```

Игнорировать:

```text
.owl/local/
.owl/cache/
.owl/tmp/
.owl/*.local.yaml
```

Пример `.gitignore`:

```gitignore
# Owl local runtime
.owl/local/
.owl/cache/
.owl/tmp/
.owl/*.local.yaml

# Optional, если пользователь не хочет хранить активные задачи в git:
# tasks/TASK-*/
# tasks/index.yaml
```

---

## 4. Пример JSON StepInvocation для агента

Команда:

```bash
owl step invocation TASK-0001 specify --json
```

Пример ответа:

```json
{
  "task": {
    "id": "TASK-0001",
    "title": "Add user CSV export",
    "kind": "composite_task",
    "workflow": "composite_feature",
    "status": "active",
    "variables": {
      "domain": "user-export",
      "risk": "medium",
      "touches_architecture": false
    }
  },
  "step": {
    "id": "design",
    "title": "Sketch design for the brief",
    "skill": "owl-step-discussion",
    "session_type": "discussion",
    "tier": "advanced"
  },
  "inputs": {
    "artifacts": {
      "brief": {
        "type": "brief",
        "uri": "file:///project/tasks/TASK-0001/brief.md"
      }
    },
    "docs": {
      "domain_spec": {
        "uri": "file:///project/docs/user-export/design.md",
        "exists": false
      }
    }
  },
  "outputs": {
    "artifacts": {
      "design": {
        "type": "design",
        "uri": "file:///project/tasks/TASK-0001/design.md",
        "template_uri": "file:///project/.owl/artifacts/design/templates/default.md"
      }
    }
  },
  "validation": {
    "artifact_type": "design",
    "required_sections": [
      "API",
      "Behavior"
    ]
  },
  "rules": {
    "must": [
      "Create or update the design artifact.",
      "Do not modify application code.",
      "Do not mark the step complete until validation passes."
    ]
  }
}
```

---

## 5. Дерево задач: пример ответа `owl task tree`

```bash
owl task tree --json
```

Пример ответа:

```json
{
  "items": [
    {
      "id": "TASK-0001",
      "title": "Add user CSV export",
      "kind": "composite_task",
      "status": "active",
      "current_step": "coordinate",
      "children": [
        {
          "id": "TASK-0002",
          "title": "Add backend endpoint",
          "kind": "task",
          "status": "ready",
          "current_step": "plan"
        },
        {
          "id": "TASK-0003",
          "title": "Add UI entry point",
          "kind": "task",
          "status": "blocked",
          "blocked_by": ["TASK-0002"]
        },
        {
          "id": "TASK-0004",
          "title": "Add tests and verification",
          "kind": "task",
          "status": "blocked",
          "blocked_by": ["TASK-0002", "TASK-0003"]
        }
      ]
    }
  ]
}
```
