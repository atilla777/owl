# Goal

Реализовать межзадачный DAG (`blocked_by`) с dep add/rm/list, проверкой ацикличности и
`owl task ready` по design — поверх P1-A (status/index/schema) и locked `IndexWriter`.

# Scope

- Модель: `blocked_by: []` в `task.yaml` + index-entry; `schemas/task.json` расширить.
- CLI: `owl task dep add|rm|list`, `owl task ready`.
- Cycle-check (переиспользуя/выделяя из `GraphBuilder`).
- Тесты + bump `Owl::VERSION` (minor) + CHANGELOG.

# Constraints

- `lib/owl/tasks/api.rb` под 100% покрытием — все новые ветки покрыть.
- Запись индекса ТОЛЬКО через locked `IndexWriter`.
- `blocked_by` каноничен; `blocks` (dependents) вычисляется обратным сканом, не хранится.
- Терминальность зависимости = `status ∈ {done, archived}` (архивная dep = завершена).
- `ready`: все `blocked_by` терминальны И задача не заклеймлена И сама не терминальна
  (`done`/`archived`/`abandoned`).
- `available`/`next`/auto-claim НЕ трогаем (scope-граница из design) — только новая
  команда `ready`.
- Обратная совместимость: legacy без `blocked_by` → `[]`.

# Checklist

1. **Схема.** В `schemas/task.json` добавить `blocked_by` (array<string>, опционально).
2. **Модель/чтение.** Создатель задач — `blocked_by: []`. `IndexRebuilder.build_index_entry`
   добавляет `blocked_by`. Reader-дефолт для legacy.
3. **Cycle-helper.** Переиспользовать `Owl::Workflows::Internal::GraphBuilder.detect_cycle`;
   если связывание неудобно (оно private + завязано на step-структуру) — выделить
   общий `Owl::Internal::CycleDetector.detect(adjacency)` и переиспользовать в обоих
   местах (workflows + tasks), без дублирования логики.
4. **Мутаторы (Api + CLI).** `add_dependency(root:, task_id:, depends_on:)`:
   валидации self-dep (`self_dependency`), существование обеих задач (`task_not_found`),
   ацикличность по графу `blocked_by` индекса + новое ребро (`dependency_cycle` с путём);
   запись task.yaml + индекс через `IndexWriter`. `remove_dependency` (no-op если нет).
   `dependencies(task_id:)` → `{blocked_by, blocks}` (blocks обратным сканом).
   CLI: `task_dep.rb` (add/rm/list с `--on`).
5. **`ready`.** `Owl::Tasks::Api.ready(root:)` фильтрует index-entries по правилу из
   constraints; сортировка priority desc, age. CLI `task_ready.rb`.
6. **Висячие ссылки.** `task delete` чистит обратные ссылки (`blocked_by`, ссылающиеся
   на удаляемую задачу) ИЛИ `ready`/cycle-check трактуют несуществующую dep устойчиво
   (не падать). Предпочесть чистку в delete; как минимум — не падать.
7. **Регистрация CLI.** Прописать `dep`/`ready` в диспетчере (`cli/api.rb`) и в
   `GROUP_SUBCOMMANDS` (`help_text.rb`).
8. **Тесты:** dep add/rm; self-dep; cycle (прямой и транзитивный); несуществующая dep;
   ready разблокирована/заблокирована; архивная dep = завершена; висячая ссылка после
   delete; index несёт blocked_by; legacy. Покрыть новые ветки `tasks/api.rb`/`cli/api.rb`.
9. Bump `Owl::VERSION` (minor) + `CHANGELOG.md`.

# Files to inspect

- `lib/owl/tasks/api.rb`, `backends/filesystem.rb`, `internal/index_rebuilder.rb`
  (build_index_entry), `index_writer.rb`, `task_schema.rb`, создатель задач,
  `internal/deleter.rb` (висячие ссылки).
- `lib/owl/workflows/internal/graph_builder.rb` (`detect_cycle`) — переиспользовать/выделить.
- `lib/owl/cli/api.rb`, `cli/internal/help_text.rb`, `cli/internal/commands/`
  (ориентир — `task_children`, новый `task_dep`, `task_ready`).
- `schemas/task.json`.
- `spec/owl/tasks/**`, `spec/owl/cli/**`, `spec/owl/workflows/**` (если выделяем cycle-helper).
- `lib/owl/version.rb`, `CHANGELOG.md`.

# Tests and verification

- Юнит/CLI на все сценарии (см. checklist 8).
- `bundle exec rspec` зелёный (после — `git checkout README.md`).
- 100% покрытие `tasks/api.rb`/`cli/api.rb`; RuboCop net-zero.

# Smoke test

```
owl task dep add TASK-B --on TASK-A --json     # B blocked_by A
owl task dep add TASK-A --on TASK-B --json     # → dependency_cycle
owl task dep list TASK-B --json                # blocked_by:[A], blocks:[]
owl task ready --json                           # B отсутствует (A не done); прочие готовые есть
owl task set-status TASK-A done --json
owl task ready --json                           # теперь B присутствует
```

# Out of scope

- deps-aware `available`/`next`/auto-claim (follow-up). Search active (TASK-0027).
  Прочие типы связей.
