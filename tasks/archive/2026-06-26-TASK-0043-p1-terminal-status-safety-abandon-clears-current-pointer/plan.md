# Plan

## Goal

Сделать терминальный статус задачи (`abandoned`/`archived`/`done`) единообразно
безопасным: `abandon` чистит current-указатель; явный доступ к терминальной
задаче через `next`/`ready-steps`/`status`/`instructions` отдаёт структурную
ошибку `task_terminal`; `owl next` без аргумента при терминальном указателе
тихо проваливается в `auto_select`; задачный `TERMINAL_STATUSES` сведён к одному
общему модулю. Реализует AC из brief и API-секцию design.

## Scope

- `lib/owl/tasks/internal/abandon_writer.rb` — очистка указателя.
- `lib/owl/orchestration/internal/task_resolver.rb` — explicit-reject vs
  current-pointer-fallback.
- Точки входа `next`/`ready-steps`/`status`/`instructions` (Api/CLI) — проброс
  `task_terminal`.
- Новый модуль задачных статусов + переиспользование в `availability_scanner` и
  `ready_scanner`.
- Версия (`Owl::VERSION`) + `CHANGELOG.md`.

## Constraints

- Доступ к состоянию только через `bin/owl`/слои Backend/Internal/Api; без
  прямого FS-доступа из оркестрации (`docs/agents/27_*`).
- `lib/owl/**/api.rb` сохраняют 100% покрытие строк (`docs/agents/30_*`).
- Шаговый `completion_gate` `TERMINAL_STATUSES` (`done`/`skipped`) НЕ трогать —
  это другое понятие; объединяем только задачный уровень.
- Reject применяется ТОЛЬКО к явно переданному id (источник `explicit`), не к
  резолву из current-указателя.
- Managed-определения (workflows/artifacts/schemas) не затрагиваются.

## Files to inspect

- `lib/owl/tasks/internal/abandon_writer.rb` — куда вставить reset (ветка persist
  и idempotent early-return).
- `lib/owl/tasks/internal/deleter.rb` + `archive/current_resetter.rb` — образец
  очистки указателя (паритет с delete, TASK-0041).
- `lib/owl/orchestration/internal/task_resolver.rb` — ветки `explicit` /
  `from_current` / `auto_select`.
- `lib/owl/orchestration/internal/` (next/instructions builders) и `lib/owl/**/api.rb`
  для `next`/`status`/`ready-steps`/`instructions` — где разрешается id и куда
  встроить terminal-проверку; найти точки, где известен «явный» vs «разрешённый» id.
- `lib/owl/tasks/internal/availability_scanner.rb`, `ready_scanner.rb` —
  текущие `TERMINAL_STATUSES`, заменить на общий модуль.
- `lib/owl/tasks/api.rb` — `current_task_id`, чтение статуса задачи (reuse).
- `lib/owl/cli/` — маппинг кодов ошибок в exit-коды (убедиться, что
  `task_terminal` даёт ненулевой exit).
- `lib/owl/version.rb`, `CHANGELOG.md`.

## Checklist

- [ ] Создать `lib/owl/tasks/internal/task_statuses.rb` с
      `TERMINAL = %w[archived abandoned done].freeze`; подключить в
      `availability_scanner.rb` и `ready_scanner.rb`, удалить локальные дубликаты
      (сохранив прочие константы ready_scanner — `NON_READY_STATUSES` и пр. — на
      основе общей).
- [ ] В `abandon_writer.rb`: вызвать `Archive::CurrentResetter.reset_if_matches`
      в `persist` и обеспечить очистку в idempotent early-return ветке (вынести
      reset так, чтобы повторный abandon тоже чинил протухший указатель).
- [ ] В `task_resolver.rb`: `from_current` — если задача терминальна, не
      возвращать `current_pointer`-резолюцию, а вызвать `auto_select(root:)`;
      добавить helper чтения статуса через `Tasks::Api`.
- [ ] Ввести общую terminal-проверку для явного id и подключить её в точках
      входа `next`/`ready-steps`/`status`/`instructions`: при `explicit` + терминал
      → `Result.err(code: :task_terminal, message: …)`.
- [ ] Убедиться, что CLI отображает `task_terminal` с ненулевым exit-кодом
      (добавить маппинг, если нужно).
- [ ] Поднять `Owl::VERSION` (minor — новый код ошибки/поведение) и добавить
      запись в `CHANGELOG.md`.
- [ ] RSpec: abandon чистит/не чистит указатель (2 кейса) + идемпотентный abandon
      чинит указатель.
- [ ] RSpec: explicit `next`/`status`/`ready-steps`/`instructions` на терминальной
      → `task_terminal`.
- [ ] RSpec: `next` без аргумента при терминальном указателе → fallback на
      `auto_select` / `no_available_task`.
- [ ] RSpec: сканеры используют общий `TERMINAL_STATUSES` (поведение фильтрации
      не изменилось).

## Tests and verification

- `bundle exec rspec` для затронутых спеков (abandon_writer, task_resolver,
  availability/ready scanners, next/status/instructions Api + CLI e2e).
- Покрытие: `lib/owl/**/api.rb` остаётся 100% (SimpleCov-гейт).
- `bundle exec rubocop` по изменённым файлам.
- E2E-проверка: воспроизвести исходный баг — abandoned-задача с current-указателем,
  убедиться, что `owl next` больше не выдаёт `dispatch_step` по ней.
- «Green» = все спеки зелёные, rubocop чист, ручной e2e даёт `task_terminal`
  (явный) и fallback (неявный).

## Out of scope

- Изменение шагового `completion_gate` `TERMINAL_STATUSES` (`done`/`skipped`).
- Авто-закрытие задачи на финальном шаге (отдельная задача TASK-0044).
- Унификация JSON-контракта available/ready (TASK-0045).
- Любые изменения managed workflows/artifacts/schemas.

## Smoke test

1. Создать задачу, поставить её current (`owl task use`), затем
   `owl task abandon` её → `owl task current` сообщает `no_current_task`.
2. `owl next <abandoned-id> --json` → `ok: false`, `code: task_terminal`,
   ненулевой exit.
3. При висящем терминальном current-указателе `owl next --json` (без id) →
   `dispatch_step` следующей доступной задачи (или `no_available_task`), но не по
   терминальной.
