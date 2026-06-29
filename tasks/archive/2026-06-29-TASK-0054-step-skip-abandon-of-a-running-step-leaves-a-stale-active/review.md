---
status: resolved
summary: >-
  Фикс TASK-0054 (осиротевший active-step lock) корректен и полон: skip снимает
  lock по match'у, abandon — безусловно для задачи, reset получает recovery-ветку
  строго при step_not_running + matching stale-lock. Семантика Steps::Api не
  изменена, lock-управление осталось в CLI-слое поверх фасадов, version + CHANGELOG
  подняты, тесты зелёные. Вердикт — accepted.
verdict: accepted
ready: true
---

# Summary

Self-review правок TASK-0054, закрывающих три течи per-task active-step lock
(`.owl/local/active_steps/<TASK-ID>.yaml`). Diff рабочего дерева проверен против
acceptance criteria брифа и решения дизайна; прогнан полный `bundle exec rspec`.

Затронуто:
- `lib/owl/cli/internal/commands/step_skip.rb` — снятие lock по match'у после skip.
- `lib/owl/cli/internal/commands/task_abandon.rb` — безусловное снятие lock задачи.
- `lib/owl/cli/internal/commands/step_reset.rb` — recovery-ветка на `step_not_running`.
- `lib/owl/version.rb` — 1.3.1 → 1.4.0 (minor).
- `CHANGELOG.md` — запись `[1.4.0]`.
- `spec/owl/cli/step_commands_spec.rb`, `spec/owl/cli/task_commands_spec.rb` — 6 кейсов.

Вердикт: **accepted** (approve / pass). Дефектов, требующих изменений кода, не найдено.

# Findings

Проверено по каждому пункту требований; все выполнены.

1. **skip снимает свой lock по match'у — OK.** `step_skip.rb#clear_active_step_lock`
   (строки 50-62) повторяет эталон из `step_reset.rb`: `active_step_lock_load` →
   `active_step_lock_matches?(task_id, step_id)` → `active_step_lock_clear`. Вызов
   добавлен после успешного `Steps::Api.skip` (только при `result.ok?`), до печати
   ответа. Lock чужого шага не срывается — подтверждено тестом «skip non-owner
   leaves another step's lock untouched».

2. **abandon снимает lock задачи безусловно — OK.** `task_abandon.rb:40`
   вызывает `active_step_lock_clear` после успешного `Tasks::Api.abandon`. Это
   корректно по дизайну (задача сбрасывается целиком). `clear` — no-op при
   отсутствии lock (`Result.ok(:absent)`), форма JSON-ответа не изменена. Добавлен
   `require_relative '../../../steps/api'`.

3. **reset recovery строго на step_not_running + matching stale-lock — OK.**
   `step_reset.rb#recover_or_fail` (строки 62-75): при `result.err?` сначала
   `unless result.code == :step_not_running → возврат исходной ошибки`. Затем
   проверка matching lock; при отсутствии matching — исходная `step_not_running`
   сохраняется (реальные «нечего ресетить» остаются видимы). Только при наличии
   matching lock — `active_step_lock_clear` + `emit_recovery` (`ok: true`,
   `recovered_stale_lock: true`, `step_status` = исходный статус, шаг не менялся).
   `result.details[:current_status]` присутствует в `Err` reset'а (api.rb:293).

4. **Прежнее поведение reset для running сохранено — OK.** Успешная ветка
   `reset` (running→`Statuses::DEFAULT`=pending) + `clear_active_step_lock` по
   match'у не тронута. Тест «reset of a running step keeps prior behaviour».

5. **Семантика Steps::Api не изменена — OK.** `Steps::Api.reset`/`skip`/`complete`
   в diff не затронуты; статусные переходы прежние. Recovery полностью в CLI-слое.

6. **Lock-управление в CLI поверх фасадов, без сырых FS — OK.** Все обращения
   идут через `Steps::Api.active_step_lock_load/matches?/clear`. Прямых
   File/FileUtils/Storage вызовов в правках CLI нет.

7. **version + CHANGELOG (Constitution §7.1) — OK.** `Owl::VERSION` 1.3.1 → 1.4.0;
   запись `[1.4.0]` описывает все три изменения. SemVer minor обоснован (новое
   поведение, без слома формата/контракта; форма JSON прежняя). `api.rb` не
   менялся → 100% line coverage для `lib/owl/**/api.rb` сохранён.

8. **Покрытие соответствует плану — OK.** Все 5 кейсов step + 1 кейс task из
   раздела «Tests and verification» плана присутствуют и проходят: skip-owner,
   skip-non-owner, reset+stale-lock recovery, reset без lock → step_not_running,
   reset running → pending, abandon+running clears lock.

# Resolution

Все находки — подтверждения, не дефекты. Изменений кода не требуется. Шаг
завершается штатно (approve). Остаточных блокеров нет.

# Remediation

Не требуется — дефектов нет.

# Residual risks

- Match-семантика skip опирается на готовый `active_step_lock_matches?`; риск
  срыва чужого lock закрыт тестом non-owner. Низкий.
- Recovery в reset меняет исход (успех вместо ошибки) только в ранее-тупиковом
  `step_not_running` + stale-lock; не маскирует другие ошибки. Низкий.
- Поведение покрыто на уровне CLI-команд (E2E через `run([...])`), что адекватно
  для лог­ики, живущей в CLI-адаптерах.
