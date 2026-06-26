---
status: approved
summary: >-
  Реализовать единую проекцию Tasks::Internal::TaskSummary (string-keyed,
  task_id + core) и применить её в available/ready/list финальным map после
  сортировки; обновить symbol-key потребителей, скиллы, major bump + changelog.
---

# Goal

Свести JSON-элемент `owl task available`/`ready`/`list` к единому контракту:
ключ идентичности `task_id` + общее ядро (`task_id, title, kind, priority,
created_at, status, workflow`) + специфичные поля поверх. Переименование
только на выводе (on-disk `index.yaml` сохраняет `id`). Ломающее изменение →
major bump.

# Checklist

1. **Создать `lib/owl/tasks/internal/task_summary.rb`** —
   `module TaskSummary; module_function; def project(entry, extra: {})`.
   Принимает сырую запись индекса (string-keyed, ключ `'id'`), возвращает
   **string-keyed** Hash в каноничном порядке:
   `'task_id'` (из `entry['id']`), затем `'title', 'kind', 'priority',
   'created_at', 'status', 'workflow'`, затем merge `extra` (тоже
   string-keyed). `status` дефолтит к `'open'`, `labels`/`blocked_by` —
   читаются вызывающим, не здесь. Чистая функция, без FS.
2. **`ready_scanner.rb`** — в `scan` финальным шагом спроецировать:
   `Result.ok(ready: sort_entries(ready).map { |e| TaskSummary.project(e,
   extra: tracker_extra(e)) })`, где `tracker_extra(e)` =
   `{ 'parent_id' => e['parent_id'], 'labels' => Array(e['labels']),
   'blocked_by' => Array(e['blocked_by']), 'archived_at' => e['archived_at'] }`.
   Сортировка (`sort_entries`, string-key `'id'`) остаётся до проекции —
   не трогаем.
3. **`backends/filesystem.rb#list`** — спроецировать `tasks:` перед
   возвратом: `tasks: index.tasks.map { |e| TaskSummary.project(e, extra:
   tracker_extra(e)) }`. Порядок индекса сохраняется (list не сортирует).
4. **`availability_scanner.rb`** — `candidate_hash` строит финальную форму
   через `TaskSummary.project(entry, extra: { 'ready_step_ids' => ready_ids,
   'reason' => "priority=#{priority}; oldest ready task" })`. Это добавляет
   в `available` core-поля `status`/`workflow` (из `entry`). Сортировку
   (`sort_by { [-c[:priority], c[:created_at], c[:task_id]] }`, строка 115)
   перевести на string-keys: `[-c['priority'], c['created_at'].to_s,
   c['task_id']]`.
5. **`ready_availability_scanner.rb`** — доступ `candidate[:task_id]`
   заменить на `candidate['task_id']` (string), `ready_id_set` остаётся на
   сырых ready-entry (`entry['id']`) — там вход сырой. Проверить, что
   `--dep-aware` отдаёт спроецированную форму (она уже спроецирована в
   AvailabilityScanner).
6. **CLI** — `task_list.rb` фильтр `t['status'] == 'abandoned'` остаётся
   рабочим (проекция сохраняет `'status'`). Никаких изменений ключей в
   CLI-слое не требуется (`available`/`ready` просто пробрасывают list).
   Проверить, что `next.rb` не читает `id`/`task_id` из available несовместимо.
7. **`schemas/task.json`** — НЕ менять (описывает on-disk `task.yaml`,
   ключ `id` — формат хранения). Подтвердить отсутствие published schema на
   вывод list-команд.
8. **Обновить in-repo потребителей**, читающих `id` из вывода
   available/ready/list: `skills/owl-orchestrator/SKILL.md`,
   `commands/owl-orchestrator.md`, `skills/owl-cli/SKILL.md`,
   `commands/owl-task-status.md`, `skills/_owl_conventions.md` и пр. —
   grep `task ready`/`task list`/`task available` и заменить упоминания
   ключа `id`→`task_id`; обновить примеры JSON. Затем `bin/owl upgrade` для
   рефреша `.claude/`/`.opencode/`.
9. **Specs** — обновить/добавить: проекция (`task_summary_spec`),
   `available`/`ready`/`list` отдают `task_id` и core-поля (нет `id`-ключа),
   tracker-extra сохранены, `--dep-aware` форма, фильтр abandoned в list
   работает, on-disk `index.yaml` по-прежнему `id`. Сохранить 100% line
   coverage `lib/owl/tasks/api.rb`.
10. **`Owl::VERSION`** — major bump (X.0.0); запись в `CHANGELOG.md` с
    описанием ломающего `id`→`task_id` в `ready`/`list`. Один коммит.

# Smoke test

```
bin/owl task available --json | python3 -c "import sys,json; e=json.load(sys.stdin)['available']; assert all('task_id' in x and 'status' in x and 'workflow' in x and 'id' not in x for x in e), e; print('available OK', len(e))"
bin/owl task ready --json     | python3 -c "import sys,json; e=json.load(sys.stdin)['ready']; assert all('task_id' in x and 'id' not in x and 'labels' in x for x in e), e; print('ready OK', len(e))"
bin/owl task list --json      | python3 -c "import sys,json; e=json.load(sys.stdin)['tasks']; assert all('task_id' in x and 'id' not in x for x in e), e; print('list OK', len(e))"
bundle exec rspec spec/owl/tasks spec/owl/cli/internal/commands 2>&1 | tail -5
```

# Scope

- `lib/owl/tasks/internal/task_summary.rb` (новый), `ready_scanner.rb`,
  `ready_availability_scanner.rb`, `availability_scanner.rb`,
  `backends/filesystem.rb` (#list).
- CLI-команды `task_available`/`task_ready`/`task_list` (проверка, правки
  только при необходимости).
- Скиллы/команды `owl-*`, читающие эти выводы.
- `lib/owl/version.rb` + `CHANGELOG.md`.
- Specs под `spec/owl/tasks` и `spec/owl/cli`.

# Constraints

- On-disk `tasks/index.yaml` и `task.yaml` сохраняют ключ `id` — формат
  хранения не мигрируем; проекция строго на выводе.
- `schemas/task.json` не меняется (описывает on-disk payload).
- Top-level имена массивов (`available`/`ready`/`tasks`) не меняются.
- Сортировка/ранжирование сохраняется идентичной (проекция — финальный map
  после сортировки).
- Доступ к Owl-состоянию только через `bin/owl` (для smoke/verify).
- 100% line coverage `lib/owl/**/api.rb`.

# Files to inspect

- `lib/owl/tasks/api.rb` (`available`, `ready`, `list` делегаты).
- `lib/owl/tasks/internal/availability_scanner.rb`
  (`candidate_hash` стр. 66-86, сортировка стр. 115).
- `lib/owl/tasks/internal/ready_scanner.rb` (`scan` стр. 39-52,
  `sort_entries` стр. 90).
- `lib/owl/tasks/internal/ready_availability_scanner.rb`
  (`candidate[:task_id]` стр. 34).
- `lib/owl/tasks/backends/filesystem.rb` (`#list` стр. 42-56).
- `lib/owl/cli/internal/commands/task_{available,ready,list}.rb`,
  `next.rb`.
- `schemas/task.json` (подтвердить, что трогать не надо).
- `skills/owl-*`, `commands/owl-*`, `skills/_owl_conventions.md`.

# Tests and verification

- `bundle exec rspec spec/owl/tasks spec/owl/cli` зелёный.
- Новый `spec/owl/tasks/internal/task_summary_spec.rb` (или в api_spec):
  проекция даёт `task_id`+core, порядок ключей, дефолты.
- Spec: `available`/`ready`/`list` контракт (task_id, нет `id`, core,
  tracker-extra, ranking-extra); `--dep-aware`; abandoned-фильтр list;
  on-disk `index.yaml` остаётся `id`.
- SimpleCov: 100% для `lib/owl/tasks/api.rb`.
- RuboCop чистый по затронутым файлам.
- Smoke-команды выше проходят.

# Out of scope

- TASK-0041 (семантика overlap ready vs available) — отдельный слой.
- `owl next`, `owl task ready-steps`, `owl task aggregate-status` — там
  `task_id` уже ссылка на задачу, не задача-объект.
- Переименование top-level контейнеров массивов.
- Миграция/смена ключа в on-disk `index.yaml`/`task.yaml`.
