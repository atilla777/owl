# Owl — План реализации

Этот документ описывает поэтапный план реализации Owl. Концептуальное описание — в [AGENTS.md](AGENTS.md), архитектура — в [ARCHITECTURE.md](ARCHITECTURE.md), требования — в [REQUIREMENTS.md](REQUIREMENTS.md).

---

## Этап 1. Минимальное ядро Owl

Цель: получить работающий CLI, который умеет читать конфиг, workflow и index.

Задачи:

```text
1. Создать Ruby-проект (Go — позже).
2. Реализовать команду owl init.
3. Создать default layout:
   - .owl/config.yaml
   - .owl/workflows.yaml
   - .owl/artifacts.yaml
   - tasks/index.yaml
   - docs/
4. Реализовать загрузку .owl/config.yaml.
5. Реализовать storage role resolver.
6. Реализовать чтение workflow registry.
7. Реализовать чтение artifact registry.
8. Реализовать базовую команду:
   owl workflow list --json
9. Реализовать:
   owl config validate --json
```

Результат этапа:

```text
Owl CLI установлен.
Проект можно инициализировать.
CLI видит workflow, artifacts и storage roles.
```

---

## Этап 2. Task management MVP

Цель: создать и хранить задачи (с поддержкой `kind: task | composite_task`).

Задачи:

```text
1. Реализовать генерацию task id:
   TASK-0001, TASK-0002, ...

2. Реализовать:
   owl task create --workflow feature --title "..." --json

3. При создании задачи:
   - добавить запись в tasks/index.yaml;
   - создать tasks/TASK-0001/task.yaml (с kind из workflow.kind);
   - создать папку tasks/TASK-0001/;
   - инициализировать steps из workflow;
   - инициализировать artifacts из workflow.

4. Реализовать:
   owl task list --json
   owl task inspect TASK-0001 --json
   owl task use TASK-0001 --json
   owl task current --json
   owl task index rebuild --json
```

Результат этапа:

```text
Можно создать задачу.
Можно выбрать текущую задачу.
Можно получить её состояние.
Index пересобирается из task.yaml файлов.
```

---

## Этап 3. Workflow graph / ready steps

Цель: CLI должен понимать, какие шаги доступны.

Задачи:

```text
1. Реализовать построение graph из workflow.steps.
2. Проверять requires.
3. Проверять статус шагов из task.yaml.
4. Поддержать статусы:
   - pending
   - ready
   - running
   - done
   - skipped
   - blocked
   - failed
5. Реализовать:
   owl task ready-steps TASK-0001 --json
6. Реализовать:
   owl step start TASK-0001 specify --json
   owl step complete TASK-0001 specify --json
   owl step skip TASK-0001 design --reason "..." --json
```

Результат этапа:

```text
Owl может вести задачу по workflow.
Оркестратор может спрашивать следующий шаг.
```

---

## Этап 4. Artifact resolution and templates

Цель: CLI должен давать агентам точные пути и шаблоны.

Задачи:

```text
1. Реализовать artifact type loading.
2. Реализовать template resolution.
3. Реализовать storage resolution для artifacts.
4. Реализовать:
   owl artifact resolve TASK-0001 brief --json
   owl artifact resolve TASK-0001 specs --json
5. Реализовать:
   owl step invocation TASK-0001 specify --json
6. В StepInvocation включать:
   - task metadata (включая kind, parent_id, children — если есть);
   - step metadata;
   - input artifacts;
   - output artifacts;
   - template_uri;
   - validation rules;
   - skill id.
```

Результат этапа:

```text
Step skill получает полную машинно-читаемую инструкцию.
Skill не должен сам вычислять пути.
```

---

## Этап 5. Artifact validation MVP

Цель: проверять созданные Markdown-артефакты.

Задачи:

```text
1. Проверять существование файла.
2. Проверять required_sections.
3. Проверять required_patterns.
4. Проверять front matter, если он указан.
5. Реализовать:
   owl artifact validate TASK-0001 brief --json
   owl artifact validate TASK-0001 specs --json
6. При step complete проверять created artifacts.
```

Результат этапа:

```text
Нельзя завершить шаг, если обязательный артефакт не создан или невалиден.
```

---

## Этап 6. Базовые workflow и artifact templates

Цель: подготовить набор стандартных workflow.

Реализовать workflow:

```text
feature
composite_feature
feature_slice
hotfix
research
refactor
```

Реализовать artifact types:

```text
brief
spec
design
decomposition
tasks
verification
issue
patch_plan
research_findings
recommendation
```

Минимальный feature workflow:

```text
brief → specify → design? → plan → apply → verify → publish → archive
```

Минимальный composite_feature workflow:

```text
brief → specify → design? → decompose → coordinate → aggregate_verify → publish → archive
```

Минимальный feature_slice workflow (для child tasks):

```text
plan → apply → verify
```

Минимальный hotfix workflow:

```text
issue → patch_plan → tasks → apply → verify → archive
```

Минимальный research workflow:

```text
question → findings → options → recommendation
```

---

## Этап 7. Подзадачи / декомпозиция

Цель: научить Owl работать с parent/child task деревом.

Задачи:

```text
1. Поддержать поля task.yaml:
   - kind: task | composite_task
   - parent_id
   - children.order
   - completion.strategy

2. Реализовать команды:
   owl task tree --json
   owl task children TASK-0001 --json
   owl task parent TASK-0002 --json
   owl task aggregate-status TASK-0001 --json
   owl task child create TASK-0001 \
     --title "..." \
     --workflow feature_slice \
     --json

3. Реализовать step skill owl.steps.decompose:
   - читает brief/specs/design;
   - предлагает разбиение;
   - создаёт decomposition.md;
   - порождает child tasks через CLI (may_create_tasks: true).

4. Реализовать step skill owl.steps.coordinate:
   - отслеживает статус children;
   - сообщает оркестратору, что делать дальше.

5. Реализовать step skill owl.steps.aggregate_verify:
   - проверяет, что все children завершили verify;
   - агрегирует verification.md children в parent.

6. Валидация:
   - child.parent_id указывает на существующий composite_task;
   - composite_task.children.order — массив существующих id;
   - circular dependencies запрещены.
```

Результат этапа:

```text
Composite task может быть разбита на child tasks.
Дерево задач видно через CLI.
Статус parent агрегируется из children.
```

---

## Этап 8. Publish to docs

Цель: реализовать обновление доменных знаний.

Задачи:

```text
1. В workflow поддержать publishes.
2. Для feature / composite_feature workflow:
   tasks/TASK-0001/specs/<domain>/spec.md
   публиковать в:
   docs/<domain>/spec.md

3. Реализовать:
   owl publish TASK-0001 --json

4. В MVP можно использовать простую стратегию:
   - если docs/<domain>/spec.md не существует — создать;
   - если существует — заменить или сохранить backup;
   - позже добавить merge/delta logic.
```

Результат этапа:

```text
Завершённая задача обновляет docs.
```

---

## Этап 9. Archive

Цель: завершать задачи.

Задачи:

```text
1. Реализовать:
   owl archive TASK-0001 --json

2. Archive должен:
   - проверить, что workflow завершён;
   - проверить, что publish выполнен, если требуется;
   - для composite task: проверить, что все children тоже готовы к архивации;
   - переместить tasks/TASK-0001 в tasks/archive/<date>-TASK-0001-<slug>;
   - переместить children (если archives_children: true);
   - обновить index.yaml;
   - отметить задачу archived/done.
```

Результат этапа:

```text
Задача проходит полный жизненный цикл.
Дерево composite task архивируется атомарно.
```

---

## Этап 10. Agent integration

Цель: подготовить работу с AI skills.

Задачи:

```text
1. Описать orchestrator skill contract.
2. Описать step skill contracts.
3. Сделать examples:
   - owl.steps.brief
   - owl.steps.specify
   - owl.steps.decompose
   - owl.steps.plan
4. Убедиться, что каждый skill работает только через CLI.
5. Подготовить инструкции для агента:
   - как получить current task;
   - как получить invocation;
   - как записать artifact;
   - как проверить artifact;
   - как завершить step;
   - как создать child task через owl task child create.
```

---

## Этап 11. Future backend abstraction

Не реализовывать в MVP, но предусмотреть архитектурно.

Нужно не зашивать файловую систему в skills.

Возможные backend в будущем:

```text
filesystem
sqlite
postgres
remote api
obsidian filesystem profile
```

CLI interface должен остаться тем же.

---

## Минимальный MVP

Самый маленький полезный MVP:

```text
1. owl init
2. .owl/config.yaml
3. .owl/workflows.yaml
4. .owl/artifacts.yaml
5. feature workflow (одиночные задачи)
6. artifact types: brief, spec, tasks
7. tasks/index.yaml
8. owl task create
9. owl task current
10. owl task ready-steps
11. owl step invocation
12. owl artifact resolve
13. owl artifact validate
14. owl step complete
```

После этого уже можно подключать orchestrator skill и step skills.

Composite/child task поддержку (Этап 7) можно добавить во вторую итерацию MVP.
