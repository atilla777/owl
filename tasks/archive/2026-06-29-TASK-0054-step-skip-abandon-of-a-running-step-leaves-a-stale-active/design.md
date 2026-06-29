---
status: shipped
summary: >-
  Lock-управление остаётся в CLI-адаптерах (как complete/reset). skip и abandon
  получают снятие active-step lock (skip — по match'у, abandon — безусловно для
  задачи). reset получает CLI-recovery: при step_not_running + наличии
  matching stale-lock — снять lock и вернуть успех вместо тупика.
---

# Context

Active-step lock (`.owl/local/active_steps/<TASK-ID>.yaml`) пишется при
`owl step start` и снимается в `owl step complete` и `owl step reset`. Управление
lock'ом исторически живёт в **CLI-слое** (`lib/owl/cli/internal/commands/`), а не
в core-методах `Steps::Api`:

- `step_complete.rb` после успешного `Steps::Api.complete` зовёт
  `active_step_lock_clear` **безусловно** (running-шаг = владелец lock'а).
- `step_reset.rb` зовёт `clear_active_step_lock` **по match'у**
  (`active_step_lock_matches?`), чтобы не сорвать чужой lock.
- `step_start.rb` пишет lock; `Steps::Api.skip/reset/complete` сами lock не трогают.

Бриф (TASK-0054) требует закрыть три течи: `skip` и `task abandon` оставляют
осиротевший lock, а `reset` для non-running шага возвращает `step_not_running`
и не даёт штатно снять stale-lock (оператор уходит в `step start --force`).

# Decision

Сохранить размещение lock-управления в CLI-адаптерах и добавить точечные снятия,
повторяя существующие паттерны:

1. **`step_skip.rb`** — после успешного `Steps::Api.skip` вызвать
   `clear_active_step_lock` **по match'у** (точная копия паттерна
   `step_reset.rb#clear_active_step_lock`: load → `matches?` → `clear`). Снимаем
   lock только если он относится к снятому шагу; чужой lock не трогаем; отсутствие
   lock'а — no-op.
2. **`task_abandon.rb`** — после успешного `Tasks::Api.abandon` снять active-step
   lock задачи через `Steps::Api.active_step_lock_clear` (**безусловно для задачи**:
   задача целиком сбрасывается, любой её running-шаг становится неактуален).
3. **`step_reset.rb`** — добавить **recovery-ветку**: если `Steps::Api.reset`
   вернул `step_not_running`, проверить, есть ли для задачи active-step lock,
   **относящийся к целевому шагу** (`matches?`). Если есть — снять lock и вернуть
   **успех** (recovery: «снят stale-lock»). Если matching-lock'а нет — вернуть
   прежнюю ошибку `step_not_running` (нечего восстанавливать, поведение не
   меняется). Семантика самого `Steps::Api.reset` (только running→pending)
   остаётся нетронутой.

Так фикс закрывает корень (skip/abandon перестают течь) и даёт штатный
аварийный выход (`reset` снимает уже накопившиеся stale-lock'и) без
`step start --force`.

# Alternatives

- **Перенести lock-clear в `Steps::Api.skip` / релакс `Steps::Api.reset`**
  (Api-слой вместо CLI). Отвергнуто: ломает текущее разделение (lock-управление
  уже целиком в CLI-адаптерах для start/complete/reset); релакс `reset` до
  «no-op-успех для non-running» размывает чёткую семантику метода и риск замаскировать
  настоящие ошибки вызывающих кодов, ожидающих `step_not_running`.
- **Отдельная команда `owl step unlock` / флаг `owl step reset --force-unlock`.**
  Отвергнуто: вводит новую CLI-поверхность ради того, что `reset` уже семантически
  означает («снять активность шага»); recovery в самом `reset` не добавляет
  поверхности и совпадает с операторской интуицией.
- **Безусловный clear в `step_skip` (как в complete).** Отвергнуто в пользу
  match-семантики: skip может применяться к pending/non-owner шагу, тогда как у
  задачи теоретически активен другой шаг — безусловный clear сорвал бы чужой lock.

# Risks

- **Маскировка ошибок в reset-recovery.** Recovery срабатывает строго при
  `step_not_running` И matching stale-lock present; при отсутствии lock'а старый
  `step_not_running` сохраняется — реальные «нечего ресетить» по-прежнему видны.
- **Match-семантика skip.** Неверный match сорвал бы чужой lock; митигируется
  переиспользованием готового `active_step_lock_matches?` и тестом «skip
  не-owner-шага не трогает чужой lock».
- **Backward compat.** Поведенческое расширение; форма JSON-ответов команд не
  меняется. Для `reset` recovery меняет исход (успех вместо ошибки) только в
  ранее-тупиковом случае — это улучшение, не слом контракта. SemVer: minor
  (новое поведение/способность), bump `Owl::VERSION` + `CHANGELOG.md`.
- **Coverage.** Затрагиваются CLI-команды и, возможно, фасады `Steps::Api`;
  обеспечить RSpec на все три ветки + сохранение 100% line coverage для любых
  правок в `lib/owl/**/api.rb`.

# API

Публичного API/`docs/`-поверхности дизайн не добавляет — изменения внутри
CLI-адаптеров поверх существующих фасадов `Steps::Api.active_step_lock_*`
(`active_step_lock_load`, `active_step_lock_matches?`, `active_step_lock_clear`)
и `Tasks::Api.abandon`. Наблюдаемые контракты:

- `owl step skip TASK STEP --reason ...` → при снятии running-owner шага также
  снимает active-step lock (по match'у). JSON-форма ответа без изменений.
- `owl task abandon TASK` → снимает active-step lock задачи. JSON-форма без изменений.
- `owl step reset TASK STEP` → при `step_not_running` + matching stale-lock
  возвращает `ok: true` (recovery, lock снят) вместо ошибки `step_not_running`;
  при отсутствии matching-lock'а — прежняя ошибка `step_not_running`.

Поскольку `merge_docs`/`publish` для этой задачи — no-op по части `docs/`
(нет публичной поверхности), раздел существует для полноты схемы.
