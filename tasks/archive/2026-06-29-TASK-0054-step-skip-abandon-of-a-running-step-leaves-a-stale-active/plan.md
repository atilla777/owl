# Goal

Закрыть три течи осиротевшего per-task active-step lock: `owl step skip` и
`owl task abandon` должны снимать lock, а `owl step reset` должен снимать stale-lock
даже для non-running шага (без `step start --force`). Реализация — в CLI-адаптерах,
повторяя готовый паттерн `step_reset.rb#clear_active_step_lock` (load → `matches?`
→ `clear`). Семантика `Steps::Api.skip/reset` не меняется.

# Checklist

- [ ] `lib/owl/cli/internal/commands/step_skip.rb` — добавить приватный
  `clear_active_step_lock(root:, options:)` (копия паттерна из `step_reset.rb`:
  `active_step_lock_load` → `active_step_lock_matches?` → `active_step_lock_clear`)
  и вызвать его после успешного `Steps::Api.skip` (только когда `result.ok?`),
  до печати success-ответа. Match по `options[:step_id]`; отсутствие/чужой lock — no-op.
- [ ] `lib/owl/cli/internal/commands/task_abandon.rb` — после успешного
  `Tasks::Api.abandon` снять active-step lock задачи через
  `Owl::Steps::Api.active_step_lock_clear(root: root, task_id: options[:task_id])`
  (безусловно для задачи — задача сбрасывается целиком). No-op, если lock'а нет.
- [ ] `lib/owl/cli/internal/commands/step_reset.rb` — добавить recovery-ветку:
  когда `Steps::Api.reset` вернул `err` с кодом `:step_not_running`, проверить
  наличие matching active-step lock (через существующий `clear_active_step_lock`-путь:
  `active_step_lock_load` + `active_step_lock_matches?`). Если matching-lock есть —
  снять его и вернуть **success** (payload отражает recovery: lock снят, статус шага
  не менялся). Если matching-lock'а нет — вернуть прежнюю ошибку `step_not_running`
  без изменений. Не трогать ветку, где `reset` успешен (running→pending).
- [ ] `lib/owl/version.rb` — поднять `Owl::VERSION` `1.3.1` → `1.4.0` (minor: новое
  поведение CLI, без слома on-disk формата/JSON-контракта).
- [ ] `CHANGELOG.md` — запись под новой версией: skip/abandon чистят active-step lock,
  reset снимает stale-lock для non-running шага (recovery вместо `step start --force`).

# Smoke test

```
# подготовка: задача с running-шагом, владеющим active-step lock
bin/owl step start <TASK> <STEP>
ls .owl/local/active_steps/<TASK>.yaml          # lock существует
bin/owl step skip <TASK> <STEP> --reason smoke  # skip running-owner
ls .owl/local/active_steps/<TASK>.yaml          # lock-файла НЕТ
bin/owl step start <TASK> <NEXT> --json         # НЕ active_step_locked

# reset-recovery: вручную оставить stale-lock (start затем skip),
# затем reset снимает lock и возвращает ok:true для non-running шага
bin/owl step reset <TASK> <STEP> --json         # ok:true, lock снят
```
Плюс полный прогон `bundle exec rspec` зелёный.

# Scope

CLI-адаптеры `step_skip.rb`, `task_abandon.rb`, `step_reset.rb`; `version.rb`;
`CHANGELOG.md`. Используются существующие фасады `Steps::Api.active_step_lock_*`
— новых публичных методов API не вводится.

# Constraints

- Lock-управление остаётся в CLI-слое (как `complete`/`reset`/`start`); сырых
  FS-доступов из CLI не вводить — только через `Steps::Api.active_step_lock_*`.
- `skip` снимает lock **по match'у** (`active_step_lock_matches?`), не безусловно —
  не сорвать чужой lock.
- `abandon` снимает lock задачи безусловно (задача целиком сброшена).
- `reset` recovery срабатывает строго при `step_not_running` И наличии matching
  stale-lock; иначе прежняя ошибка сохраняется (не маскировать реальные ошибки).
- Семантика core `Steps::Api.reset`/`skip` (статусные переходы) — без изменений.
- Bump `Owl::VERSION` + `CHANGELOG.md` в том же коммите (Constitution §7.1).

# Files to inspect

- `lib/owl/cli/internal/commands/step_reset.rb` — эталон `clear_active_step_lock`
  (load → matches? → clear), копируется в skip и в reset-recovery.
- `lib/owl/cli/internal/commands/step_complete.rb` — пример безусловного clear.
- `lib/owl/cli/internal/commands/step_skip.rb`, `task_abandon.rb` — точки правки.
- `lib/owl/steps/api.rb` — фасады `active_step_lock_load/matches?/clear`, метод `skip`.
- `lib/owl/steps/internal/active_step_lock.rb` — примитивы lock'а (`load`/`clear`/`matches?`).
- `lib/owl/tasks/api.rb` — `Tasks::Api.abandon`.

# Tests and verification

- `spec/owl/cli/step_commands_spec.rb` — добавить примеры:
  (1) skip running-owner шага снимает active-step lock; (2) skip шага, не
  владеющего lock'ом, не трогает чужой lock; (3) reset non-running шага со
  stale-lock возвращает ok и снимает lock; (4) reset non-running шага БЕЗ lock'а
  по-прежнему возвращает `step_not_running`; (5) reset running-шага — прежнее
  поведение (pending + lock снят).
- `spec/owl/cli/task_commands_spec.rb` — abandon задачи с running-шагом снимает
  active-step lock.
- Прогон: `bundle exec rspec` зелёный; проверить, что правки не задели
  `lib/owl/**/api.rb` без покрытия (100% line coverage для api.rb сохранён).

# Out of scope

- Изменение семантики статусных переходов `Steps::Api.skip`/`reset`/`complete`.
- Новые CLI-команды/флаги (`owl step unlock`, `reset --force-unlock`) — отвергнуто
  в design.
- Перенос lock-управления из CLI-слоя в `Steps::Api` core-методы.
- Любые изменения claim/heartbeat-лиз (отдельный механизм, не active-step lock).
