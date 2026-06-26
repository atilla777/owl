---
status: shipped
summary: >-
  Обобщить Steps::Internal::ArchiveFinalizer в TaskFinalizer: при завершении
  шага, после которого все шаги терминальны, и нетерминальном статусе задачи —
  выставить status=done через Tasks::Api.set_status и сбросить current-указатель.
  Поведение archive-пути сохранить.
---

# Context

`Steps::Api.complete` (`lib/owl/steps/api.rb:73`) после успешной записи статуса
шага (`status: done`) вызывает `Steps::Internal::ArchiveFinalizer.call`
(строки 123–125), а в идемпотентной ветке — из `idempotent_complete`
(строки 402–407).

`ArchiveFinalizer` (`lib/owl/steps/internal/archive_finalizer.rb`):

```ruby
return false unless payload['status'].to_s == 'archived'
return false unless all_steps_terminal?(payload['steps'])
CurrentResetter.reset_if_matches(...)
```

То есть финализация задачи (перевод в терминальное состояние + освобождение
current-указателя) сегодня привязана к статусу `archived`, который ставит только
шаг `archive`. Workflow без `archive` (`quick`: `brief → implement →
commit_push`) после завершения терминального шага остаётся `status: open` —
никто не переводит **задачу** в терминальный статус. Следствия описаны в брифе
(quick-never-terminal; done-but-open в available/ready; неосвобождённый
указатель).

Доступные строительные блоки:
- `Owl::Tasks::Api.set_status(root:, task_id:, status:)` (`lib/owl/tasks/api.rb:45`)
  — установка статуса задачи через backend под per-task lock (TASK-0035).
- `Tasks::Internal::Archive::CurrentResetter.reset_if_matches` — сброс
  current-указателя, уже используемый ArchiveFinalizer.
- `Tasks::Internal::TaskStatuses::TERMINAL = %w[archived abandoned done]`
  (`lib/owl/tasks/internal/task_statuses.rb:16`) — единый источник терминальных
  статусов (TASK-0043).
- `ArchiveFinalizer.all_steps_terminal?` — критерий «все шаги done/skipped».

Фильтры `availability_scanner.rb` / `ready_scanner.rb` уже исключают терминальные
статусы, поэтому установка `done` сама убирает залипание — отдельная правка
фильтрации не нужна.

# Decision

Обобщить `Steps::Internal::ArchiveFinalizer` в `Steps::Internal::TaskFinalizer`
(переименование + расширение зоны ответственности), вызываемый из тех же двух
точек `Steps::Api.complete`. Сигнатуру дополнить `root:` (нужен для
`Tasks::Api.set_status`); `tasks_root:` / `local_state_root:` остаются для чтения
payload и сброса указателя.

Алгоритм `TaskFinalizer.call(root:, tasks_root:, local_state_root:, task_id:)`:

1. Прочитать payload (`TaskReader.read`); `return false` если не прочитан.
2. **Общий гейт:** `return false unless all_steps_terminal?(payload['steps'])`
   (все шаги в `done`/`skipped`). Пока есть `pending`/`running`/`blocked` —
   ничего не делаем.
3. `status = payload['status'].to_s`.
4. Ветвление:
   - `status` **не** в `TERMINAL` → перевести задачу в терминал:
     `Tasks::Api.set_status(root:, task_id:, status: 'done')`, затем
     `CurrentResetter.reset_if_matches(...)`. Вернуть `true`.
   - `status == 'archived'` → сохранить текущее поведение: только
     `CurrentResetter.reset_if_matches(...)` (статус уже терминальный, не
     перезаписываем). Вернуть `true`.
   - прочий терминальный (`done` / `abandoned`) → no-op (`return false`):
     `done` уже финализирован (идемпотентность), `abandoned` уже освободил
     указатель при `owl task abandon` (TASK-0043).

Свойства:
- **Идемпотентность.** Повторный `complete` на `done`-задаче идёт по ветке
  «прочий терминальный» → no-op; `set_status` не вызывается, `task.yaml` не
  переписывается.
- **Archive-путь без изменений.** feature/hotfix/refactor/composite на шаге
  `archive` получают `archived`; к моменту завершения `commit_push` статус уже
  `archived` → ветка `archived` → только сброс указателя, ровно как сейчас.
- **Композитный родитель.** Гейтнутые шаги (`archive`/`commit_push` с
  `gate: children_complete`) не завершаются, пока дети не готовы, поэтому
  `all_steps_terminal?` ложно и авто-close не срабатывает преждевременно.

Изменение в `Steps::Api.complete`: обе точки вызова передают `root:` в
`TaskFinalizer.call`. Имя `ArchiveFinalizer` удаляется (вместе с `require`),
вводится `task_finalizer.rb`.

# Decision: публичный контракт CLI/JSON

Ответ `owl step complete` дополняется **необязательным** аддитивным полем
`task_status` (строка) — финальный статус задачи после финализации (`done` для
авто-close; для archive-пути поле отражает `archived`). Поле добавляется только
когда финализация что-то изменила или статус терминален; отсутствие поля =
задача ещё в работе. Это обратносовместимое расширение (новый ключ), существующие
потребители не ломаются. `owl next` уже возвращает `done`/исключает терминальные
задачи без изменений.

# Alternatives

1. **Добавить шаг `archive` в `quick` workflow.** Отклонено: чинит только
   `quick`, противоречит замыслу `quick` («minimal: no archive»), меняет
   seed-контент и не закрывает общий класс «workflow без archive». Не
   соответствует заголовку задачи.

2. **Новый отдельный модуль рядом с `ArchiveFinalizer` (не трогать
   существующий).** Отклонено: дублирует `all_steps_terminal?` и логику сброса
   указателя, оставляет две почти одинаковые финализации с риском расхождения.
   Обобщение в один `TaskFinalizer` чище и переиспользует существующее.

3. **Фильтровать «open + все шаги done» прямо в availability/ready-scanner
   (вычислять терминальность на лету, не меняя статус).** Отклонено: оставляет
   `status: open` на диске (вводящее в заблуждение состояние), не освобождает
   current-указатель, размазывает понятие «завершено» по нескольким сканерам и
   усложняет инварианты TASK-0043 (единый TERMINAL_STATUSES). Переход статуса —
   единственная точка истины.

4. **Ставить `archived` вместо `done` для quick.** Отклонено: `archived`
   означает перенос в архивную зону (`owl archive` пишет архивную копию,
   `archived_at`); ставить его без фактической архивации — ложь о состоянии.
   `done` — корректный «логически завершён, не заархивирован» терминал.

# Risks

- **Двойная запись `task.yaml` в одном `complete`.** `complete` пишет статус
  шага (`StatusWriter`), затем `TaskFinalizer` — статус задачи
  (`Tasks::Api.set_status`). Обе мутации идут под per-task lock (TASK-0035),
  блокировка реентерабельна/последовательна — гонки нет, но это два отдельных
  write. Приемлемо; покрыть тестом, что после `complete` терминального шага и
  статус шага `done`, и статус задачи `done`.
- **Регрессия archive-пути.** Если ветвление перепутает archived → done,
  сломается feature/composite. Митигировать тестом «archive → commit_push
  оставляет `archived`, не `done`».
- **Слой/layering.** `Steps::Internal` обращается к `Tasks::Api` — допустимо
  (Internal → Api другого модуля — публичная грань, не прямой FS). `set_status`
  не лезет в FS напрямую из Internal. Соответствует
  `27_Owl_Ruby_code_architecture.md`.
- **Покрытие публичного API.** Если меняется грань `lib/owl/**/api.rb`
  (добавление поля в ответ `step complete` формируется на уровне CLI-команды, не
  в `api.rb`) — обеспечить 100% покрытие новых строк в затронутых `api.rb`.
- **Совместимость потребителей gem.** Изменение поведения в `lib/**` требует
  bump `Owl::VERSION` (patch) + CHANGELOG; распространение через
  `owl self-update` → `owl upgrade`.

# API

Внутренний модуль (не CLI-поверхность):

```
Owl::Steps::Internal::TaskFinalizer.call(
  root:, tasks_root:, local_state_root:, task_id:
) -> Boolean   # true, если задача была финализирована (переведена в done
               # ИЛИ освобождён указатель archive-пути); false — no-op.
```

Заменяет `Owl::Steps::Internal::ArchiveFinalizer` (удаляется). Вызовы из
`Steps::Api.complete` и `Steps::Api.idempotent_complete` обновляются на новое
имя и передачу `root:`.

CLI / JSON (публичная грань, публикуется в `docs/`):

- `owl step complete <TASK> <STEP>` — поведение: при завершении шага, после
  которого все шаги задачи терминальны, и нетерминальном статусе задача
  переводится в `status: done`, current-указатель освобождается.
- Ответ дополняется необязательным полем `task_status` (string, additive,
  обратносовместимо): финальный статус задачи, когда финализация применилась;
  иначе поле отсутствует.
- Прочие команды (`owl next`, `owl task available`, `owl task ready`,
  `owl task current`) без изменений сигнатур — они уже корректно реагируют на
  терминальный `done`.
