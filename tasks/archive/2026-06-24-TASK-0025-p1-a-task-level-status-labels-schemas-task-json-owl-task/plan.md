# Goal

Реализовать трекер-метаданные задачи по design: explicit `status` + `labels` в
`task.yaml`+index, `schemas/task.json` с валидацией, CLI `owl task set-status` /
`label add|rm` / `query`, переиспользуя locked `IndexWriter` и `Owl::Validation`.

# Scope

- Модель: новые поля `status`/`labels` в `task.yaml` + index-entry.
- Схема: `schemas/task.json` + валидация на мутациях.
- CLI: `set-status`, `label add|rm`, `query`.
- Тесты + bump `Owl::VERSION` (minor) + CHANGELOG.

# Constraints

- `lib/owl/tasks/api.rb` под правилом 100% покрытия `**/api.rb` — все новые ветки
  покрыть.
- Запись индекса ТОЛЬКО через locked `IndexWriter` (TASK-0021) — не плодить прямые
  записи.
- Обратная совместимость: legacy `task.yaml` без полей → `status: open`, `labels: []`
  по чтению; без принудительного rewrite.
- `schemas/task.json`: `additionalProperties: true`; legacy-поля опциональны.
- Статус ортогонален шагам; `archived` ставится системно при archive; дефолт `open`.
- `query` фильтрует ИНДЕКС (не скан task.yaml); AND-комбинация фильтров.

# Checklist

1. **Схема.** Добавить `schemas/task.json` (id/title/workflow/kind/parent_id/priority/
   created_at/steps/artifacts + `status` enum [open,in_progress,blocked,on_hold,done,
   archived] + `labels` array<string>; `additionalProperties: true`). Проверить
   существующий `Owl::Validation::Api.task` (lib/owl/validation/api.rb:23) — что он уже
   делает; подключить схему туда или расширить.
2. **Модель/чтение.** Создатель задач проставляет `status: open`, `labels: []`.
   Reader/нормализация: legacy без полей → дефолты. `IndexRebuilder.build_index_entry`
   добавляет `status`/`labels` в index-entry.
3. **Мутаторы (Api + CLI).** В `Owl::Tasks::Api`: `set_status`, `add_label`,
   `remove_label` (валидируют через схему/enum, пишут task.yaml + перезапись индекса
   через `IndexWriter`). CLI-команды `task_set_status.rb`, `task_label.rb`
   (`add`/`rm`). Идемпотентность label add; rm несуществующего — no-op/понятный ответ.
4. **Query.** `Owl::Tasks::Api.query(root:, filters:)` фильтрует index-entries
   (AND по status/label/priority/parent/workflow). CLI `task_query.rb` с опциями
   `--status --label --priority --parent --workflow --json`. `archive` системно ставит
   `status: archived` (расширить archive-путь).
5. **Регистрация CLI.** Прописать новые подкоманды в диспетчере (`lib/owl/cli/api.rb`)
   и в `help_text.rb` `GROUP_SUBCOMMANDS` (чтобы FF1 subcommand-help их показывал).
6. **Тесты:** статус set+валидация enum; label add/rm идемпотентность; query
   AND-фильтры; схема (валид/невалид); обратная совместимость legacy-файла; index
   несёт поля. Покрыть новые ветки `tasks/api.rb`/`cli/api.rb` до 100%.
7. Bump `Owl::VERSION` (minor) + `CHANGELOG.md`.

# Files to inspect

- `lib/owl/tasks/api.rb`, `lib/owl/tasks/backends/filesystem.rb`,
  `lib/owl/tasks/internal/index_rebuilder.rb` (build_index_entry), `index_writer.rb`,
  создатель задач, archive-путь (`internal/archive/*`).
- `lib/owl/validation/api.rb` (`task` метод), `lib/owl/validation/internal/json_schema_walker.rb`.
- `schemas/` (добавить `task.json`; ориентир — `workflow.json`).
- `lib/owl/cli/api.rb` (диспетчер + GROUP_SUBCOMMANDS), `lib/owl/cli/internal/help_text.rb`,
  `lib/owl/cli/internal/commands/` (новые команды; ориентир — `task_set_priority`/`task_children`).
- `spec/owl/tasks/**`, `spec/owl/cli/**`, `spec/owl/validation/**`.
- `lib/owl/version.rb`, `CHANGELOG.md`, `owl-cli.gemspec` (schemas glob — проверить, что `schemas/**` пакуется).

# Tests and verification

- Юнит/CLI на каждый сценарий (status/labels/query/schema/legacy/index).
- `bundle exec rspec` зелёный (после — `git checkout README.md`).
- 100% покрытие `tasks/api.rb` и `cli/api.rb`; RuboCop net-zero.

# Smoke test

```
owl task create --workflow feature --title T --json   # → status:open, labels:[]
owl task set-status TASK-ID on_hold --json
owl task label add TASK-ID backend --json
owl task query --status open --label backend --json    # → отфильтровано (AND)
owl task query --status on_hold --json                  # → находит TASK-ID
owl task set-status TASK-ID bogus --json                # → invalid_status
```

# Out of scope

- Deps DAG + ready (TASK-0026), search active (TASK-0027), assignees/due/epics.
