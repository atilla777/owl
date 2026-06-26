# Goal

Обобщить финализацию задачи: завершение шага, после которого все шаги задачи
терминальны (`done`/`skipped`), при нетерминальном статусе задачи переводит её в
`status: done` и освобождает current-указатель. Реализуется переименованием
`Steps::Internal::ArchiveFinalizer` в `TaskFinalizer` с дополнительной веткой
«нетерминальный статус → set done», без изменения archive-пути.

# Checklist

- [ ] `lib/owl/steps/internal/task_finalizer.rb` — новый файл: модуль
  `Owl::Steps::Internal::TaskFinalizer` (на базе текущего `ArchiveFinalizer`).
  Сигнатура `call(root:, tasks_root:, local_state_root:, task_id:)`. Логика:
  читать payload (`TaskReader.read`, `return false` при err); общий гейт
  `return false unless all_steps_terminal?(steps)`; затем по статусу:
  не-терминальный → `Owl::Tasks::Api.set_status(root:, task_id:, status: 'done')`
  + `CurrentResetter.reset_if_matches(...)`, вернуть `true`;
  `status == 'archived'` → только `CurrentResetter.reset_if_matches(...)`,
  вернуть `true`; прочий терминальный → `return false`. Сохранить
  `all_steps_terminal?` и `TERMINAL_STEP_STATUSES = %w[done skipped]`. Терминал
  статуса задачи брать из `Owl::Tasks::Internal::TaskStatuses::TERMINAL`.
  Добавить `require_relative '../../tasks/api'` и
  `require_relative '../../tasks/internal/task_statuses'`.
- [ ] `lib/owl/steps/internal/archive_finalizer.rb` — удалить (заменён
  `task_finalizer.rb`).
- [ ] `lib/owl/steps/api.rb` — заменить
  `require_relative 'internal/archive_finalizer'` на
  `require_relative 'internal/task_finalizer'`; в `complete` (строки ~123–125)
  и `idempotent_complete` (~402–407) заменить `Internal::ArchiveFinalizer.call`
  на `Internal::TaskFinalizer.call(root: root, tasks_root: ..., local_state_root:
  ..., task_id: ...)` — пробросить `root:` (в `complete` он в параметрах; в
  `idempotent_complete` добавить параметр `root` и передать из `complete`).
- [ ] `lib/owl/cli/internal/commands/step_complete.rb` (или модуль форматирования
  ответа `step complete`) — добавить в JSON-ответ необязательное поле
  `task_status`: финальный статус задачи, когда финализация применилась
  (читать актуальный статус после `complete`); иначе поле не добавлять.
  Найти точную команду: `grep -rn "def.*complete\|step complete" lib/owl/cli`.
- [ ] `lib/owl/version.rb` — bump `Owl::VERSION` (patch: фикс/обратносовместимое
  поведение).
- [ ] `CHANGELOG.md` — запись о авто-close задачи на терминальном шаге
  (quick-never-terminal + done-but-open) в том же коммите.
- [ ] `spec/owl/steps/internal/task_finalizer_spec.rb` — новый юнит-спек на
  `TaskFinalizer.call`: (а) не-терминальный статус + все шаги done → задача
  `done` + сброс указателя; (б) `archived` + все шаги done → указатель сброшен,
  статус остаётся `archived`; (в) не все шаги терминальны → no-op (false);
  (г) уже `done`/`abandoned` → no-op (false); (д) указатель чужой задачи не
  трогается.
- [ ] `spec/owl/steps/api_spec.rb` — добавить интеграционные кейсы на `complete`:
  quick-подобная задача (все шаги, кроме завершаемого, уже done/skipped) →
  после `complete` терминального шага статус задачи `done`; идемпотентный
  повторный `complete` на `done`-шаге не меняет статус; archive-кейс
  (status предварительно `archived`) → `complete` оставляет `archived`.

# Smoke test

```
# В песочнице/тестовом repo с quick-задачей, где brief+implement уже done:
bin/owl step complete <TASK> commit_push --json   # ожидаем task_status: done
bin/owl task current --json                        # не должно быть этой задачи
bin/owl task available --json                      # задачи нет в списке
# Регрессия archive-пути:
bundle exec rspec spec/owl/steps/api_spec.rb spec/owl/steps/internal/task_finalizer_spec.rb
```

# Scope

Финализация задачи в `Steps::Api.complete` (через
`Steps::Internal::TaskFinalizer`) и аддитивное поле `task_status` в ответе
`owl step complete`. Затрагивает `lib/owl/steps/**`, точку форматирования ответа
CLI, `version.rb`, `CHANGELOG.md`, спеки.

# Constraints

- Доступ к `tasks/` — только через backend/Api; `set_status` идёт через
  `Tasks::Api.set_status` (per-task lock, TASK-0035), без прямого FS из Internal.
- Терминальные статусы задачи — единый источник
  `TaskStatuses::TERMINAL` (TASK-0043); не плодить локальные списки.
- Поведение archive-содержащих workflow (feature/hotfix/refactor/composite) не
  меняется: `archived` не перезаписывается в `done`.
- Bump `Owl::VERSION` + CHANGELOG в том же коммите (изменение `lib/**/*.rb`).
- Поле `task_status` — аддитивное и необязательное (обратная совместимость JSON).

# Files to inspect

- `lib/owl/steps/internal/archive_finalizer.rb` (исходник для обобщения).
- `lib/owl/steps/api.rb` (`complete`, `idempotent_complete`, require-список).
- `lib/owl/tasks/api.rb:45` (`set_status`).
- `lib/owl/tasks/internal/archive/current_resetter.rb` (`reset_if_matches`).
- `lib/owl/tasks/internal/task_statuses.rb` (`TERMINAL`).
- `lib/owl/cli/internal/commands/` — команда `step complete` (формирование JSON).
- `lib/owl/tasks/internal/availability_scanner.rb`,
  `lib/owl/tasks/internal/ready_scanner.rb` (убедиться: `done` уже исключается —
  правок не требуется).

# Tests and verification

- Новый `spec/owl/steps/internal/task_finalizer_spec.rb` (юнит, см. чеклист).
- Расширенный `spec/owl/steps/api_spec.rb` (интеграция `complete`).
- `bundle exec rspec` зелёный; RuboCop чистый.
- 100% покрытие новых строк в любом затронутом `lib/owl/**/api.rb`.

# Out of scope

- Добавление шага `archive` в `quick` workflow (отклонено в дизайне).
- Изменение фильтрации в availability/ready-сканерах (не требуется — `done` уже
  терминален).
- Изменение поведения `owl archive` и composite-гейтов.
- Любые новые CLI-команды или изменение существующих сигнатур.
