---
status: passed
summary: >-
  Унифицированный JSON-контракт available/ready/list (единый task_id + общее ядро)
  реализован через Tasks::Internal::TaskSummary; вся тест-сюита зелёная (2049/0),
  rubocop чист на затронутых файлах, smoke-команды проходят, on-disk index.yaml
  сохраняет id, major bump 1.0.0 + CHANGELOG.
---

# Summary

Реализована единая проекция элемента списка задач и применена в трёх командах:

- Создан `lib/owl/tasks/internal/task_summary.rb` — чистая функция
  `TaskSummary.project(entry, extra:)`: принимает сырую запись индекса
  (string-keyed, ключ `id`), возвращает string-keyed Hash в каноничном порядке
  `task_id, title, kind, priority, created_at, status, workflow` + merge `extra`.
  `status` дефолтит к `open`, `priority` нормализуется к Integer.
- `availability_scanner.rb` — `candidate_hash` строится через `TaskSummary.project`
  (это ДОБАВЛЯЕТ в `available` core-поля `status`/`workflow`), сортировка
  переведена на string-keys.
- `ready_scanner.rb` — финальный `map` через `TaskSummary.project` после
  `sort_entries` (сортировка осталась на сырых `id`); добавлен `tracker_extra`.
- `ready_availability_scanner.rb` — пересечение и `ready_id_set` переведены на
  `task_id` (обе ветки `available`, включая `--dep-aware`, отдают единый контракт).
- `backends/filesystem.rb#list` — проекция `tasks:` с tracker-extra, порядок
  индекса сохранён.
- Обновлены внутренние потребители вывода (symbol→string и `id`→`task_id`):
  `claim_service` (claim --next), `orchestration/task_resolver` (auto_select для
  `owl next`), `steps/invocation_builder` (child_ids), `commit_push/api`
  (исключение чужих task-dir), `status/views` (children), `recall/corpus_builder`.
- `Owl::VERSION` 0.23.1 → **1.0.0** (major, ломающий JSON-контракт), запись в
  `CHANGELOG.md`.

On-disk хранилище (`tasks/index.yaml`, `task.yaml`, `schemas/task.json`) НЕ
тронуто — переименование только на выводе. `owl task query` остаётся вне охвата
(сырой `id`). Скиллы/команды `owl-*` уже ссылались на идентичность через
`task_id`, поэтому правок там не потребовалось (grep подтвердил отсутствие
чтения ключа `id` из этих выводов).

# Commands

- `bundle exec rspec spec/owl/tasks spec/owl/cli` → 717 examples, 0 failures.
- `bundle exec rspec` (полная сюита) → 2049 examples, 0 failures, 1 pending
  (предсуществующий pending в storage backend contract), exit 0.
- Проверка gate: "Public API files below 100%" — список пуст, т.е. все
  `lib/owl/**/api.rb` на 100% line coverage (включая затронутый
  `commit_push/api.rb`).
- `bundle exec rubocop` по 11 затронутым lib-файлам и 11 spec-файлам → no
  offenses (одна правка длины строки в `commit_push/api_spec.rb`).
- Smoke:
  - `owl task available --json` → 3 элемента, у каждого `task_id`, `status`,
    `workflow`, без `id`.
  - `owl task ready --json` → 4 элемента, у каждого `task_id`, `labels`, без `id`.
  - `owl task list --json` → 5 элементов, у каждого `task_id`, без `id`.
  - `owl next --json` → `ok:true`, резолв через current_pointer на TASK-0045
    (auto_select-ветка с `top['task_id']` покрыта спеком task_resolver).

# Outcomes

- Все три команды отдают единый элемент: общее ядро `task_id, title, kind,
  priority, created_at, status, workflow` + специфика (`available` →
  `ready_step_ids, reason`; `ready`/`list` → `parent_id, labels, blocked_by,
  archived_at`). Подтверждено и спеками (порядок ключей, отсутствие `id`,
  отсутствие symbol-`:task_id`), и live smoke-выводом.
- `available` впервые несёт `status` и `workflow`; `--dep-aware` отдаёт ту же
  форму.
- On-disk `index.yaml` по-прежнему содержит `id` (спек в `filesystem_spec`
  читает файл напрямую и проверяет это).
- Добавлен `spec/owl/tasks/internal/task_summary_spec.rb` (проекция: порядок
  ключей, дефолты status/priority, merge extra, отсутствие `id`).
- Обновлены спеки контракта: `availability_scanner_spec`,
  `ready_availability_scanner_spec`, `api_spec` (.available + .list),
  `api_dependencies_spec` (.ready), `filesystem_spec` (list + on-disk id),
  `task_dep_commands_spec`, `task_commands_spec`, `claim_lease_spec`,
  `index_writer_spec`, `commit_push/api_spec` (stubs list-вывода).

# Not run

Ничего релевантного не пропущено: запускалась и таргетная (`spec/owl/tasks`,
`spec/owl/cli`), и полная сюита.

# Failures or blockers

Блокеров нет. Промежуточно падали 3 спека `commit_push/api_spec` (стабы
list-вывода со старым ключом `id`) и серия спеков, читавших symbol-ключи из
`available` — все приведены к новому контракту, итог зелёный.

# Residual risks

- Известный health-wart (rspec может завершаться ненулевым кодом при частичном
  прогоне из-за SimpleCov-gate) не проявился: полный прогон exit 0, частичный
  0 failures.
- Предсуществующий offense `Layout/LineLength` в `task_commands_spec.rb` (строка
  с `task delete --force`, 125 симв.) не трогался — он вне затронутых строк и
  присутствует в HEAD.
- Ломающее изменение: consumer-проекты (re/Rrrog, tetris) должны подхватить
  новый контракт `ready`/`list` через `owl upgrade` после публикации гема 1.0.0.
